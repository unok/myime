@echo off
setlocal enabledelayedexpansion

echo ============================================
echo   Zenzai Integration Test - Build and Run
echo ============================================
echo.

cd /d "%~dp0"

:: Find Visual Studio
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo [ERROR] vswhere.exe not found
    exit /b 1
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set "VS_PATH=%%i"
)

if not defined VS_PATH (
    echo [ERROR] Visual Studio not found
    exit /b 1
)

echo Found Visual Studio: %VS_PATH%

:: Setup environment
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to setup VC environment
    exit /b 1
)

echo.
echo --- Compiling test ---
cl.exe /nologo /EHsc /O2 /Fe:zenzai_test.exe zenzai_test.cpp

if errorlevel 1 (
    echo [ERROR] Compilation failed
    exit /b 1
)

echo.
echo --- Running test ---
echo.

:: Run the test
zenzai_test.exe
set TEST_RESULT=%ERRORLEVEL%

echo.
if %TEST_RESULT% EQU 0 (
    echo [SUCCESS] All tests passed
) else (
    echo [FAILURE] Some tests failed
)

exit /b %TEST_RESULT%
