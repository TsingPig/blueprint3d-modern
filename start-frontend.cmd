@echo off
setlocal

set "URL=http://localhost:3000/zh"
set "START_SCRIPT=%~dp0scripts\start-local.ps1"
set "OPEN_SCRIPT=%~dp0scripts\open-3d-browser.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%START_SCRIPT%" -CheckOnly
set "FRONTEND_STATUS=%ERRORLEVEL%"

if "%FRONTEND_STATUS%"=="2" (
  start "Blueprint3D Frontend" powershell -NoProfile -ExecutionPolicy Bypass -File "%START_SCRIPT%"
) else if not "%FRONTEND_STATUS%"=="0" (
  exit /b %FRONTEND_STATUS%
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$url = '%URL%'; for ($i = 0; $i -lt 180; $i++) { try { $response = Invoke-WebRequest -UseBasicParsing $url -TimeoutSec 3; if ($response.StatusCode -eq 200) { exit 0 } } catch { }; Start-Sleep -Seconds 1 }; exit 1"

if errorlevel 1 (
  echo Frontend is still starting or failed to start. Check the Blueprint3D Frontend window.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%OPEN_SCRIPT%" -Url "%URL%"
if errorlevel 1 exit /b 1
