@echo off
setlocal EnableDelayedExpansion

echo ==============================================
echo Building Swift Engine for MyIme
echo ==============================================
echo.

:: Set paths
set "ROOT_DIR=%~dp0"
set "SWIFT_DIR=%ROOT_DIR%src\swift-engine"
set "BUILD_DIR=%ROOT_DIR%build"
set "OUTPUT_DIR=%BUILD_DIR%\x64\release"

:: Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: Check if Swift is installed
where swift >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Swift is not installed or not in PATH
    echo Please install Swift 6.2.1 or later and try again.
    exit /b 1
)

:: Get Visual Studio environment
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: vswhere.exe not found
    echo Please install Visual Studio 2022 with C++ workload
    exit /b 1
)

:: Find Visual Studio installation
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set "VS_PATH=%%i"
)

if not defined VS_PATH (
    echo ERROR: Visual Studio 2022 with C++ workload not found
    exit /b 1
)

:: Setup Visual Studio environment
echo Setting up Visual Studio environment...
call "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul 2>&1

:: Change to Swift directory
cd /d "%SWIFT_DIR%"

:: Clean previous build
echo Cleaning previous build...
if exist .build rmdir /s /q .build

:: Build Swift package
echo.
echo Building Swift package...
echo Using Package.swift for remote dependencies...

:: Copy remote package configuration
copy /y Package-remote.swift Package.swift >nul

:: Build in release mode
swift build -c release --arch x86_64

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Swift build failed
    exit /b 1
)

:: Copy the built library to output directory
echo.
echo Copying output files...

:: Find the DLL in .build directory
set "DLL_FOUND="
for /f "delims=" %%F in ('dir /s /b "%SWIFT_DIR%\.build\release\*.dll" 2^>nul') do (
    set "DLL_PATH=%%F"
    set "DLL_NAME=%%~nxF"
    set "DLL_FOUND=1"
)

if not defined DLL_FOUND (
    echo ERROR: No DLL found in build output
    exit /b 1
)

:: Copy DLL to output directory
copy /y "!DLL_PATH!" "%OUTPUT_DIR%\azookey-engine.dll" >nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to copy DLL
    exit /b 1
)

echo Copied: azookey-engine.dll

:: Copy dependencies if any
echo.
echo Checking for dependencies...

:: Copy Swift runtime libraries
set "SWIFT_RUNTIME=%SystemDrive%\Library\Developer\Toolchains\unknown-Asserts-development.xctoolchain\usr\bin"
if exist "%SWIFT_RUNTIME%" (
    echo Copying Swift runtime libraries...
    copy /y "%SWIFT_RUNTIME%\*.dll" "%OUTPUT_DIR%\" >nul 2>&1
)

echo.
echo ==============================================
echo Build completed successfully!
echo ==============================================
echo.
echo Output: %OUTPUT_DIR%\azookey-engine.dll
echo.

endlocal
exit /b 0