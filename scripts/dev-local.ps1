[CmdletBinding()]
param(
  [switch]$SetupOnly,
  [switch]$Stop,
  [switch]$Foreground,
  [switch]$RefreshDeps,
  [string]$NodeVersion = '22.22.3',
  [string]$PnpmVersion = '9'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'local-env.ps1')

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
  Write-Host 'Start the app later with .\scripts\dev-local.ps1'
  return
}

Stop-RepoNextProcesses -RepoRoot $toolchain.RepoRoot

if ($Stop) {
  Write-Host 'Stopped repo-local Next.js dev/start processes.'
  return
}

$appRoot = Join-Path $toolchain.RepoRoot 'app'

if ($Foreground) {
  Push-Location $appRoot
  try {
    & $toolchain.PnpmCmd dev
  }
  finally {
    Pop-Location
  }
  return
}

$stdoutLog = Join-Path $toolchain.RepoRoot '.tools\dev-server.stdout.log'
$stderrLog = Join-Path $toolchain.RepoRoot '.tools\dev-server.stderr.log'
$pidFile = Join-Path $toolchain.RepoRoot '.tools\dev-server.pid'

foreach ($path in @($stdoutLog, $stderrLog, $pidFile)) {
  if (Test-Path $path) {
    Remove-Item $path -Force
  }
}

$startProcessArgs = @{
  FilePath = $toolchain.NodeExe
  ArgumentList = @($toolchain.PnpmCli, 'dev')
  WorkingDirectory = $appRoot
  RedirectStandardOutput = $stdoutLog
  RedirectStandardError = $stderrLog
  WindowStyle = 'Hidden'
  PassThru = $true
}

$process = Start-Process @startProcessArgs

Set-Content -Path $pidFile -Value $process.Id

Write-Host "Started Next.js dev server in the background (PID $($process.Id))."
Write-Host "App URL: http://localhost:3000"
Write-Host "Stdout log: $stdoutLog"
Write-Host "Stderr log: $stderrLog"
Write-Host 'Stop it with .\scripts\dev-local.ps1 -Stop'
Write-Host 'Run in the current terminal with .\scripts\dev-local.ps1 -Foreground'