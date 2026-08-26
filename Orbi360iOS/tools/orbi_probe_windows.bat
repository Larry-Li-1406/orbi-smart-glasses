@echo off
setlocal
cd /d "%~dp0"

where py >nul 2>nul
if %errorlevel%==0 (
  py -3 "%~dp0orbi_probe.py" %*
) else (
  python "%~dp0orbi_probe.py" %*
)

echo.
pause
