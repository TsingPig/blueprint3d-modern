[CmdletBinding()]
param(
  [string]$Url = 'http://localhost:3000/zh',
  [switch]$ProbeOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-ChromePath {
  $chromeRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LocalAppData) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $candidates = $chromeRoots | ForEach-Object {
    Join-Path $_ 'Google\Chrome\Application\chrome.exe'
  }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return (Resolve-Path $candidate).Path
    }
  }

  throw 'Google Chrome was not found. Install Chrome or update scripts\open-3d-browser.ps1 with the correct path.'
}

function New-FreeTcpPort {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  try {
    $listener.Start()
    return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
  }
  finally {
    $listener.Stop()
  }
}

function New-WebGLProbeUrl {
  $probeScript = @'
(() => {
  const result = { ok: false, vendor: '', renderer: '', error: '' };

  try {
    const canvas = document.createElement('canvas');
    const gl = canvas.getContext('webgl2') || canvas.getContext('webgl') || canvas.getContext('experimental-webgl');

    if (!gl) {
      throw new Error('WebGL context was not created.');
    }

    const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
    result.ok = true;
    result.vendor = debugInfo ? gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL) : gl.getParameter(gl.VENDOR);
    result.renderer = debugInfo ? gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
  } catch (error) {
    result.error = error && error.message ? error.message : String(error);
  }

  document.title = 'BP3D:' + btoa(unescape(encodeURIComponent(JSON.stringify(result))));
  document.body.textContent = JSON.stringify(result, null, 2);
})();
'@

  $html = @"
<!doctype html><html><head><meta charset="utf-8"><title>BP3D:pending</title></head><body><script>$probeScript</script></body></html>
"@
  return 'data:text/html;charset=utf-8,' + [System.Uri]::EscapeDataString($html)
}

function ConvertFrom-ProbeTitle {
  param(
    [Parameter(Mandatory)]
    [string]$Title
  )

  if (-not $Title.StartsWith('BP3D:')) {
    return $null
  }

  $encoded = $Title.Substring(5)
  if ([string]::IsNullOrWhiteSpace($encoded) -or $encoded -eq 'pending') {
    return $null
  }

  $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
  return $json | ConvertFrom-Json
}

function Invoke-ChromeWebGLProbe {
  param(
    [Parameter(Mandatory)]
    [string]$ChromePath,
    [Parameter(Mandatory)]
    [string[]]$Chrome3DArgs,
    [Parameter(Mandatory)]
    [string]$RepoRoot
  )

  $port = New-FreeTcpPort
  $probeProfile = Join-Path $RepoRoot ".tools\blueprint3d-chrome-probe-$PID"
  $probeUrl = New-WebGLProbeUrl
  $probeProcess = $null
  $targetId = $null

  if (Test-Path $probeProfile) {
    Remove-Item -Recurse -Force -Path $probeProfile
  }
  New-Item -ItemType Directory -Force -Path $probeProfile | Out-Null

  try {
    $probeArgs = @(
      "--user-data-dir=$probeProfile",
      "--remote-debugging-port=$port",
      '--new-window'
    ) + $Chrome3DArgs + @($probeUrl)

    $probeProcess = Start-Process -FilePath $ChromePath -ArgumentList $probeArgs -PassThru
    $deadline = (Get-Date).AddSeconds(15)

    while ((Get-Date) -lt $deadline) {
      try {
        $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/list" -TimeoutSec 1
        foreach ($target in @($targets)) {
          $probeResult = ConvertFrom-ProbeTitle -Title ([string]$target.title)
          if ($null -eq $probeResult) {
            continue
          }

          $targetId = $target.id
          if (-not $probeResult.ok) {
            throw "Chrome WebGL probe failed: $($probeResult.error)"
          }

          return $probeResult
        }
      }
      catch {
        if ($_.Exception.Message -like 'Chrome WebGL probe failed:*') {
          throw
        }
      }

      Start-Sleep -Milliseconds 250
    }

    throw 'Chrome WebGL probe timed out before a result was available.'
  }
  finally {
    if ($targetId) {
      try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/close/$targetId" -TimeoutSec 1 | Out-Null
      }
      catch {
      }
    }

    if ($probeProcess -and -not $probeProcess.HasExited) {
      Stop-Process -Id $probeProcess.Id -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -Recurse -Force -Path $probeProfile -ErrorAction SilentlyContinue
  }
}

$repoRoot = Get-RepoRoot
$chromePath = Get-ChromePath
$chrome3DArgs = @(
  '--enable-webgl',
  '--ignore-gpu-blocklist',
  '--use-angle=d3d11',
  '--enable-gpu-rasterization',
  '--no-first-run',
  '--no-default-browser-check'
)

$probeResult = Invoke-ChromeWebGLProbe -ChromePath $chromePath -Chrome3DArgs $chrome3DArgs -RepoRoot $repoRoot
Write-Host "Chrome WebGL probe ok: $($probeResult.renderer)"

if ($ProbeOnly) {
  return
}

$profilePath = Join-Path $repoRoot '.tools\blueprint3d-chrome-profile'
New-Item -ItemType Directory -Force -Path $profilePath | Out-Null

$openArgs = @(
  "--user-data-dir=$profilePath",
  '--new-window'
) + $chrome3DArgs + @($Url)

Start-Process -FilePath $chromePath -ArgumentList $openArgs | Out-Null