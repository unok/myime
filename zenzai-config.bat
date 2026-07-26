@echo off
setlocal

set "KEY=HKCU\Software\Mozc"
set "VALUE=ZenzaiEnabled"

if /I "%~1"=="on" goto on
if /I "%~1"=="off" goto off
if /I "%~1"=="status" goto status

echo Usage: %~nx0 on^|off^|status
exit /b 1

:on
reg add "%KEY%" /v "%VALUE%" /t REG_DWORD /d 1 /f
if errorlevel 1 exit /b %errorlevel%
echo Zenzai AI conversion is enabled.
echo Restart mozc_server to apply the change. You can run restart-ime.bat or re-login.
exit /b 0

:off
reg add "%KEY%" /v "%VALUE%" /t REG_DWORD /d 0 /f
if errorlevel 1 exit /b %errorlevel%
echo Zenzai AI conversion is disabled.
echo Restart mozc_server to apply the change. You can run restart-ime.bat or re-login.
exit /b 0

:status
set "CUR="
for /f "tokens=3" %%a in ('reg query "%KEY%" /v "%VALUE%" 2^>nul ^| findstr /i "%VALUE%"') do set "CUR=%%a"
if not defined CUR (
    echo ZenzaiEnabled is not set. Zenzai is ENABLED ^(default^).
    exit /b 0
)
if "%CUR%"=="0x0" (
    echo Zenzai is DISABLED ^(ZenzaiEnabled=0^).
) else (
    echo Zenzai is ENABLED ^(ZenzaiEnabled=%CUR%^).
)
exit /b 0
