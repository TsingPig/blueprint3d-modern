[CmdletBinding()]
param(
  [switch]$SetupOnly,
  [switch]$RefreshDeps,
  [switch]$SkipBuild,
  [switch]$CheckOnly,
  [string]$NodeVersion = '22.22.3',
  [string]$PnpmVersion = '9'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'local-env.ps1')

function Get-ProcessWithAncestors {
  param(
    [Parameter(Mandatory)]
    [int]$ProcessId
  )

  $processes = @()
  $seen = [System.Collections.Generic.HashSet[int]]::new()
  $currentId = $ProcessId

  while ($currentId -gt 0 -and $seen.Add($currentId)) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $currentId" -ErrorAction SilentlyContinue
    if ($null -eq $process) { break }

    $processes += $process
    $currentId = [int]$process.ParentProcessId
  }

  return @($processes)
}

function Test-ProcessTreeContainsRepo {
  param(
    [Parameter(Mandatory)]
    [object[]]$Processes,
    [Parameter(Mandatory)]
    [string]$RepoRoot
  )

  $repoRootLower = $RepoRoot.ToLowerInvariant()
  foreach ($process in $Processes) {
    $commandLine = $process.CommandLine
    if ($commandLine -and $commandLine.ToLowerInvariant().Contains($repoRootLower)) {
      return $true
    }
  }

  return $false
}

function Test-ProcessTreeCommandLine {
  param(
    [Parameter(Mandatory)]
    [object[]]$Processes,
    [Parameter(Mandatory)]
    [string[]]$Patterns
  )

  foreach ($process in $Processes) {
    $commandLine = $process.CommandLine
    if ([string]::IsNullOrWhiteSpace($commandLine)) {
      continue
    }

    $commandLineLower = $commandLine.ToLowerInvariant()
    foreach ($pattern in $Patterns) {
      if ($commandLineLower -match $pattern) {
        return $true
      }
    }
  }

  return $false
}

function Get-FrontendPortStatus {
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot
  )

  $listeners = @(Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue)
  if ($listeners.Count -eq 0) {
    return [pscustomobject]@{ State = 'Available' }
  }

  $devPatterns = @(
    'pnpm(\.cjs|\.cmd)?"?\s+dev\b',
    'next\\dist\\bin\\next"?\s+dev\b',
    '\bnext(\.cmd)?\s+dev\b'
  )
  $stablePatterns = @(
    'pnpm(\.cjs|\.cmd)?"?\s+start\b',
    'next\\dist\\bin\\next"?\s+start\b',
    '\bnext(\.cmd)?\s+start\b',
    'next\\dist\\server\\lib\\start-server\.js'
  )
  $staleProcessIds = @()

  foreach ($listener in $listeners) {
    $processes = Get-ProcessWithAncestors -ProcessId ([int]$listener.OwningProcess)
    $owner = $processes | Select-Object -First 1

    if ($null -eq $owner) {
      $staleProcessIds += [int]$listener.OwningProcess
      continue
    }

    if (-not (Test-ProcessTreeContainsRepo -Processes $processes -RepoRoot $RepoRoot)) {
      return [pscustomobject]@{
        State = 'Blocked'
        ProcessId = [int]$listener.OwningProcess
        ProcessName = $owner.Name
        CommandLine = $owner.CommandLine
      }
    }

    if (Test-ProcessTreeCommandLine -Processes $processes -Patterns $devPatterns) {
      $staleProcessIds += [int]$listener.OwningProcess
      continue
    }

    if (Test-ProcessTreeCommandLine -Processes $processes -Patterns $stablePatterns) {
      continue
    }

    $staleProcessIds += [int]$listener.OwningProcess
  }

  if ($staleProcessIds.Count -gt 0) {
    return [pscustomobject]@{
      State = 'Stale'
      ProcessIds = @($staleProcessIds | Sort-Object -Unique)
    }
  }

  return [pscustomobject]@{ State = 'Stable' }
}

function Stop-StaleRepoFrontend {
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,
    [Parameter(Mandatory)]
    [int[]]$ProcessIds
  )

  Stop-RepoNextProcesses -RepoRoot $RepoRoot

  foreach ($processId in $ProcessIds) {
    try {
      Stop-Process -Id $processId -Force -ErrorAction Stop
    }
    catch {
    }
  }
}

function Resolve-FrontendPortForStartup {
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot
  )

  $status = Get-FrontendPortStatus -RepoRoot $RepoRoot

  switch ($status.State) {
    'Available' {
      return $true
    }
    'Stable' {
      Write-Host 'Frontend is already running on http://localhost:3000.'
      return $false
    }
    'Stale' {
      Write-Host 'Restarting stale repo-local frontend process on port 3000.'
      Stop-StaleRepoFrontend -RepoRoot $RepoRoot -ProcessIds $status.ProcessIds
      return $true
    }
    'Blocked' {
      throw "Port 3000 is already used by PID $($status.ProcessId) ($($status.ProcessName)). Stop that process or free the port before starting Blueprint3D."
    }
  }
}

$repoRoot = Get-RepoRoot

if ($CheckOnly) {
  $shouldStart = Resolve-FrontendPortForStartup -RepoRoot $repoRoot
  if ($shouldStart) {
    exit 2
  }

  exit 0
}

if (-not $SetupOnly) {
  $shouldStart = Resolve-FrontendPortForStartup -RepoRoot $repoRoot
  if (-not $shouldStart) {
    return
  }
}

$toolchain = Initialize-RepoLocalToolchain -NodeVersion $NodeVersion -PnpmVersion $PnpmVersion
$depsReady = Test-RepoDependenciesInstalled -RepoRoot $toolchain.RepoRoot

if ($RefreshDeps -or -not $depsReady) {
  Install-RepoDependencies -Toolchain $toolchain
}

if ($SetupOnly) {
  Write-Host ''
  Write-Host 'Local toolchain is ready.'
  Write-Host "Node: $($toolchain.NodeExe)"
  Write-Host "pnpm: $($toolchain.PnpmCmd)"
  Write-Host 'Start the app later with .\scripts\start-local.ps1'
  return
}

$shouldStart = Resolve-FrontendPortForStartup -RepoRoot $toolchain.RepoRoot
if (-not $shouldStart) {
  return
}

Push-Location (Join-Path $toolchain.RepoRoot 'app')
try {
  if (-not $SkipBuild) {
    & $toolchain.PnpmCmd build
  }

  & $toolchain.PnpmCmd start
}
finally {
  Pop-Location
}
