@echo off
setlocal EnableDelayedExpansion

echo ==============================================
echo Building Swift Engine (Standalone Mode)
echo ==============================================
echo.
echo Note: This build script attempts to build without Visual Studio.
echo If it fails, please use build-swift-final.bat instead.
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

echo Swift found:
swift --version
echo.

:: Try to find Windows SDK
echo Checking for Windows SDK...
set "WIN_SDK_FOUND="

:: Check common Windows SDK locations
for %%v in (10.0.26220.0 10.0.22621.0 10.0.22000.0 10.0.19041.0 10.0.18362.0 10.0.17763.0) do (
    if exist "%ProgramFiles(x86)%\Windows Kits\10\Include\%%v\ucrt" (
        set "WIN_SDK_VERSION=%%v"
        set "WIN_SDK_FOUND=1"
        goto :sdk_found
    )
)

:sdk_found
if not defined WIN_SDK_FOUND (
    echo WARNING: Windows SDK not found at expected locations
    echo Build may fail. Continuing anyway...
) else (
    echo Found Windows SDK version: %WIN_SDK_VERSION%
)

:: Change to Swift directory
cd /d "%SWIFT_DIR%"

:: Clean previous build
echo.
echo Cleaning previous build...
if exist .build rmdir /s /q .build

:: Build Swift package
echo.
echo Building Swift package...
echo Using Package.swift for remote dependencies...

:: Copy local package configuration (with patched AzooKey)
copy /y Package-local.swift Package.swift >nul

:: Try to build without explicit SDK paths first
echo.
echo Attempting standalone build...
swift build -c release --arch x86_64 2>&1 | findstr /V "warning"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo First build attempt failed. Trying with minimal environment setup...
    
    :: Set minimal required environment variables
    if defined WIN_SDK_VERSION (
        set "INCLUDE=%ProgramFiles(x86)%\Windows Kits\10\Include\%WIN_SDK_VERSION%\ucrt;%INCLUDE%"
        set "LIB=%ProgramFiles(x86)%\Windows Kits\10\Lib\%WIN_SDK_VERSION%\ucrt\x64;%LIB%"
    )
    
    :: Try build again
    swift build -c release --arch x86_64 2>&1 | findstr /V "warning"
    
    if !ERRORLEVEL! NEQ 0 (
        echo.
        echo ERROR: Swift build failed even with minimal setup.
        echo Please use build-swift-final.bat which includes proper Visual Studio setup.
        exit /b 1
    )
)

echo.
echo Build completed successfully!

:: Copy the built library to output directory
echo.
echo Copying output files...

:: Find the DLL in .build directory
set "DLL_FOUND="
set "DLL_PATH=%SWIFT_DIR%\.build\release\azookey-engine.dll"
if exist "%DLL_PATH%" (
    set "DLL_NAME=azookey-engine.dll"
    set "DLL_FOUND=1"
)

if not defined DLL_FOUND (
    echo ERROR: No DLL found in build output
    echo Looking in: %SWIFT_DIR%\.build\release\
    dir "%SWIFT_DIR%\.build\release\" 2>nul
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
echo Checking for Swift runtime dependencies...

:: Look for Swift runtime in various possible locations
set "SWIFT_RUNTIME="
for %%p in (
    "%SystemDrive%\Library\Developer\Toolchains\unknown-Asserts-development.xctoolchain\usr\bin"
    "%ProgramFiles%\Swift\Toolchains\*\usr\bin"
    "%LocalAppData%\Programs\Swift\Toolchains\*\usr\bin"
) do (
    if exist "%%~p" (
        set "SWIFT_RUNTIME=%%~p"
        goto :runtime_found
    )
)

:runtime_found
if defined SWIFT_RUNTIME (
    echo Found Swift runtime at: %SWIFT_RUNTIME%
    echo Copying Swift runtime libraries...
    for %%f in ("%SWIFT_RUNTIME%\*.dll") do (
        if exist "%%f" (
            copy /y "%%f" "%OUTPUT_DIR%\" >nul 2>&1
        )
    )
) else (
    echo WARNING: Swift runtime not found. The built DLL may have runtime dependencies.
)

echo.
echo ==============================================
echo Build completed!
echo ==============================================
echo.
echo Output: %OUTPUT_DIR%\azookey-engine.dll
echo.
echo If this build doesn't work properly, please install Visual Studio 2022
echo with C++ workload and use build-swift-final.bat instead.
echo.

endlocal
exit /b 0