@echo off
setlocal

set "KEY=HKCU\Software\Mozc"
set "VALUE=ZenzaiEnabled"
set "GPU_VALUE=ZenzaiUseGpu"

if /I "%~1"=="on" goto on
if /I "%~1"=="off" goto off
if /I "%~1"=="gpu-on" goto gpu_on
if /I "%~1"=="gpu-off" goto gpu_off
if /I "%~1"=="status" goto status

echo Usage: %~nx0 on^|off^|gpu-on^|gpu-off^|status
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

:gpu_on
reg add "%KEY%" /v "%GPU_VALUE%" /t REG_DWORD /d 1 /f
if errorlevel 1 exit /b %errorlevel%
echo Zenzai GPU ^(Vulkan^) inference is enabled.
echo Restart mozc_server to apply the change. You can run restart-ime.bat or re-login.
exit /b 0

:gpu_off
reg add "%KEY%" /v "%GPU_VALUE%" /t REG_DWORD /d 0 /f
if errorlevel 1 exit /b %errorlevel%
echo Zenzai GPU ^(Vulkan^) inference is disabled.
echo Restart mozc_server to apply the change. You can run restart-ime.bat or re-login.
exit /b 0

:status
set "CUR="
set "GPU_CUR="
for /f "tokens=3" %%a in ('reg query "%KEY%" /v "%VALUE%" 2^>nul ^| findstr /i "%VALUE%"') do set "CUR=%%a"
for /f "tokens=3" %%a in ('reg query "%KEY%" /v "%GPU_VALUE%" 2^>nul ^| findstr /i "%GPU_VALUE%"') do set "GPU_CUR=%%a"
if not defined CUR (
    echo Zenzai is ENABLED ^(ZenzaiEnabled not set, default^).
) else if "%CUR%"=="0x0" (
    echo Zenzai is DISABLED ^(ZenzaiEnabled=0^).
) else (
    echo Zenzai is ENABLED ^(ZenzaiEnabled=%CUR%^).
)
if not defined GPU_CUR (
    echo Zenzai GPU is DISABLED ^(ZenzaiUseGpu not set, default^).
) else if "%GPU_CUR%"=="0x1" (
    echo Zenzai GPU is ENABLED ^(ZenzaiUseGpu=%GPU_CUR%^).
) else (
    echo Zenzai GPU is DISABLED ^(ZenzaiUseGpu=%GPU_CUR%^).
)
exit /b 0
