[CmdletBinding()]
param(
  [string]$NodeVersion = '22.22.3',
  [string]$PnpmVersion = '9'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'local-env.ps1')

$toolchain = Initialize-RepoLocalToolchain -NodeVersion $NodeVersion -PnpmVersion $PnpmVersion

Write-Host ''
Write-Host 'Repo-local Node.js and pnpm are active in this shell.'
Write-Host "Node: $($toolchain.NodeExe)"
Write-Host "pnpm: $($toolchain.PnpmCmd)"
Write-Host "pnpm store: $($toolchain.PnpmStore)"
Write-Host 'You can now run pnpm install or pnpm dev in this terminal.'