Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Initialize-RepoLocalToolchain {
  [CmdletBinding()]
  param(
    [string]$NodeVersion = '22.22.3',
    [string]$PnpmVersion = '9'
  )

  $repoRoot = Get-RepoRoot
  $toolsRoot = Join-Path $repoRoot '.tools'
  $nodeDirName = "node-v$NodeVersion-win-x64"
  $nodeRoot = Join-Path $toolsRoot $nodeDirName
  $nodeExe = Join-Path $nodeRoot 'node.exe'
  $npmCmd = Join-Path $nodeRoot 'npm.cmd'
  $pnpmRoot = Join-Path $toolsRoot 'pnpm'
  $pnpmBinRoot = Join-Path $pnpmRoot 'node_modules\.bin'
  $pnpmCmd = Join-Path $pnpmBinRoot 'pnpm.cmd'
  $pnpmCli = Join-Path $pnpmRoot 'node_modules\pnpm\bin\pnpm.cjs'
  $npmCache = Join-Path $repoRoot '.npm-cache'
  $pnpmStore = Join-Path $repoRoot '.pnpm-store'

  foreach ($path in @($toolsRoot, $pnpmRoot, $npmCache, $pnpmStore)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
  }

  if (-not (Test-Path $nodeExe)) {
    $archivePath = Join-Path $toolsRoot "$nodeDirName.zip"
    $downloadUrl = "https://nodejs.org/dist/v$NodeVersion/$nodeDirName.zip"

    Write-Host "Downloading Node.js $NodeVersion to $toolsRoot ..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath
    Expand-Archive -Path $archivePath -DestinationPath $toolsRoot -Force
    Remove-Item $archivePath -Force
  }

  $env:Path = "$nodeRoot;$pnpmBinRoot;$env:Path"
  $env:npm_config_cache = $npmCache
  $env:npm_config_store_dir = $pnpmStore

  if (-not (Test-Path $pnpmCmd)) {
    Write-Host "Installing pnpm@$PnpmVersion into $pnpmRoot ..."
    & $npmCmd install --prefix $pnpmRoot "pnpm@$PnpmVersion"
  }

  return [pscustomobject]@{
    RepoRoot = $repoRoot
    NodeExe = $nodeExe
    NpmCmd = $npmCmd
    PnpmCmd = $pnpmCmd
    PnpmCli = $pnpmCli
    PnpmStore = $pnpmStore
  }
}

function Test-RepoDependenciesInstalled {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot
  )

  return (Test-Path (Join-Path $RepoRoot 'node_modules')) -and
    (Test-Path (Join-Path $RepoRoot 'app\node_modules'))
}

function Install-RepoDependencies {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [pscustomobject]$Toolchain
  )

  Push-Location $Toolchain.RepoRoot
  try {
    & $Toolchain.PnpmCmd install --store-dir $Toolchain.PnpmStore

    Push-Location (Join-Path $Toolchain.RepoRoot 'app')
    try {
      & $Toolchain.PnpmCmd install --store-dir $Toolchain.PnpmStore
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Stop-RepoNextProcesses {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot
  )

  $repoRootLower = $RepoRoot.ToLowerInvariant()
  $directProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    $commandLine = $_.CommandLine

    if ([string]::IsNullOrWhiteSpace($commandLine)) {
      return $false
    }

    $commandLineLower = $commandLine.ToLowerInvariant()
    return $commandLineLower.Contains($repoRootLower) -and (
      $commandLineLower -match 'pnpm\.cjs"\s+(dev|start)\b' -or
      $commandLineLower -match 'next\\dist\\bin\\next"\s+(dev|start)\b' -or
      $commandLineLower -match '\bnext\s+(dev|start)\b'
    )
  })

  if ($directProcesses.Count -eq 0) {
    return
  }

  $targetIds = [System.Collections.Generic.HashSet[int]]::new()
  foreach ($process in $directProcesses) {
    [void]$targetIds.Add([int]$process.ProcessId)
  }

  $childProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    $targetIds.Contains([int]$_.ParentProcessId)
  })

  $allProcesses = @($directProcesses + $childProcesses) | Sort-Object ProcessId -Unique
  foreach ($process in ($allProcesses | Sort-Object ProcessId -Descending)) {
    try {
      Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
    }
    catch {
      # Ignore already-exited processes during cleanup.
    }
  }
}