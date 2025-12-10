@echo off
setlocal

echo ==============================================
echo Building Mozc 64-bit Dynamic
echo ==============================================
echo.

set "ROOT_DIR=%~dp0"
set "MOZC_SRC=%ROOT_DIR%mozc\src"

:: Add depot_tools to PATH if it exists
if exist "%MOZC_SRC%\third_party\depot_tools" (
    set "PATH=%MOZC_SRC%\third_party\depot_tools;%PATH%"
)

:: Try to find ninja in common locations
where ninja >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo Found ninja in PATH
) else (
    echo Looking for ninja...
    if exist "C:\src\depot_tools\ninja.exe" (
        set "PATH=C:\src\depot_tools;%PATH%"
        echo Found ninja in C:\src\depot_tools
    ) else if exist "%USERPROFILE%\depot_tools\ninja.exe" (
        set "PATH=%USERPROFILE%\depot_tools;%PATH%"
        echo Found ninja in %USERPROFILE%\depot_tools
    ) else (
        echo ERROR: ninja not found. Please run this from VS Developer Command Prompt
        echo or install depot_tools and add it to PATH.
        exit /b 1
    )
)

cd /d "%MOZC_SRC%"

echo.
echo Building mozc_server (64-bit dynamic)...
ninja -C out_win\ReleaseDynamic_x64 mozc_server
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Build failed
    exit /b 1
)

echo.
echo Build completed successfully!
echo Output: %MOZC_SRC%\out_win\ReleaseDynamic_x64\mozc_server.exe
echo.

endlocal
exit /b 0
