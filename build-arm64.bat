@echo off
setlocal EnableDelayedExpansion

:: ==============================================
:: MyIME Build Script - ARM64
:: ==============================================
:: This script builds the ARM64 version:
:: 1. Check dependencies
:: 2. Build Swift DLL (cross-compile from x64)
:: 3. Copy llama.cpp dependencies
:: 4. Build Mozc with Bazel (includes MSI installer)
::
:: Note: ARM64 Swift cross-compilation may fail due to
:: Swift Package Manager limitations. In that case,
:: use GitHub Actions or native ARM64 machine.
:: ==============================================

set "ROOT_DIR=%~dp0"
set "SWIFT_DIR=%ROOT_DIR%src\swift-engine"
set "MOZC_SRC=%ROOT_DIR%mozc\src"
set "BUILD_DIR=%ROOT_DIR%build"
set "OUTPUT_DIR=%BUILD_DIR%\arm64\release"

echo ==============================================
echo MyIME Build Script - ARM64
echo ==============================================
echo.

:: ==============================================
:: Step 1: Check Dependencies
:: ==============================================
echo [Step 1/4] Checking dependencies...
echo.

set "DEPS_OK=1"

:: Check Swift
echo Checking Swift...
where swift >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Swift not found in PATH
    echo   Please install Swift 6.2.1 or later from:
    echo   https://www.swift.org/download/
    set "DEPS_OK=0"
) else (
    for /f "tokens=*" %%v in ('swift --version 2^>^&1 ^| findstr /R "Swift version"') do (
        echo   [OK] %%v
    )
)

:: Check Visual Studio
echo.
echo Checking Visual Studio...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo   [ERROR] vswhere.exe not found
    echo   Please install Visual Studio 2022 with C++ workload
    set "DEPS_OK=0"
) else (
    for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do (
        set "VS_PATH=%%i"
    )
    if defined VS_PATH (
        echo   [OK] Visual Studio found at: !VS_PATH!

        :: Find MSVC version directory
        set "MSVC_PATH="
        for /d %%v in ("!VS_PATH!\VC\Tools\MSVC\*") do (
            set "MSVC_PATH=%%v"
        )

        if defined MSVC_PATH (
            :: Check ARM64 cross-compiler
            if exist "!MSVC_PATH!\bin\Hostx64\arm64\cl.exe" (
                echo   [OK] ARM64 cross-compiler found
            ) else (
                echo   [ERROR] ARM64 cross-compiler not found
                echo   Please install "MSVC v143 - VS 2022 C++ ARM64 build tools" via Visual Studio Installer:
                echo     1. Open Visual Studio Installer
                echo     2. Click "Modify" on VS 2022
                echo     3. Go to "Individual components" tab
                echo     4. Search for "ARM64"
                echo     5. Check "MSVC v143 - VS 2022 C++ ARM64 build tools ^(Latest^)"
                echo     6. Click "Modify" to install
                set "DEPS_OK=0"
            )
        ) else (
            echo   [ERROR] MSVC tools not found
            set "DEPS_OK=0"
        )
    ) else (
        echo   [ERROR] Visual Studio 2022 with C++ workload not found
        set "DEPS_OK=0"
    )
)

:: Check Python
echo.
echo Checking Python...
where python >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Python not found in PATH
    set "DEPS_OK=0"
) else (
    for /f "tokens=*" %%v in ('python --version 2^>^&1') do (
        echo   [OK] %%v
    )
)

:: Check Bazelisk
echo.
echo Checking Bazelisk...
where bazelisk >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Bazelisk not found in PATH
    set "DEPS_OK=0"
) else (
    echo   [OK] Bazelisk found
)

:: Check Windows SDK
echo.
echo Checking Windows SDK...
set "WIN_SDK_FOUND="
for %%v in (10.0.26220.0 10.0.22621.0 10.0.22000.0 10.0.19041.0 10.0.18362.0 10.0.17763.0) do (
    if exist "%ProgramFiles(x86)%\Windows Kits\10\Include\%%v\ucrt" (
        set "WIN_SDK_VERSION=%%v"
        set "WIN_SDK_FOUND=1"
        goto :sdk_check_done
    )
)
:sdk_check_done
if defined WIN_SDK_FOUND (
    echo   [OK] Windows SDK %WIN_SDK_VERSION%
) else (
    echo   [ERROR] Windows SDK not found
    set "DEPS_OK=0"
)

:: Check llama.cpp ARM64 dependencies
echo.
echo Checking llama.cpp ARM64 dependencies...
set "LLAMA_BUILD_ARM64=%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows-arm64"
if exist "%LLAMA_BUILD_ARM64%\ggml.dll" (
    echo   [OK] llama.cpp ARM64 DLLs found
) else (
    echo   [WARNING] llama.cpp ARM64 DLLs not found at %LLAMA_BUILD_ARM64%
    echo   Run build-llama-arm64.bat to build ARM64 llama.cpp DLLs.
)

:: Summary
echo.
if "%DEPS_OK%"=="0" (
    echo ==============================================
    echo [ERROR] Missing dependencies. Please install them and try again.
    echo ==============================================
    exit /b 1
)

echo All dependencies found!
echo.

:: ==============================================
:: Step 2: Build Swift DLL
:: ==============================================
echo [Step 2/4] Building Swift DLL for ARM64...
echo.

:: Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: Find MSVC ARM64 libraries
set "MSVC_ARM64_LIB="
for /d %%v in ("%VS_PATH%\VC\Tools\MSVC\*") do (
    if exist "%%v\lib\arm64" set "MSVC_ARM64_LIB=%%v\lib\arm64"
)

:: Find Windows SDK ARM64 libraries
set "WIN_SDK_ARM64_UCRT="
set "WIN_SDK_ARM64_UM="
for %%v in (10.0.26100.0 10.0.22621.0 10.0.22000.0 10.0.19041.0 10.0.18362.0) do (
    if exist "%ProgramFiles(x86)%\Windows Kits\10\Lib\%%v\ucrt\arm64" (
        set "WIN_SDK_ARM64_UCRT=%ProgramFiles(x86)%\Windows Kits\10\Lib\%%v\ucrt\arm64"
        set "WIN_SDK_ARM64_UM=%ProgramFiles(x86)%\Windows Kits\10\Lib\%%v\um\arm64"
        goto :found_sdk_arm64
    )
)
:found_sdk_arm64

if not defined MSVC_ARM64_LIB (
    echo [ERROR] MSVC ARM64 libraries not found
    exit /b 1
)
if not defined WIN_SDK_ARM64_UCRT (
    echo [ERROR] Windows SDK ARM64 libraries not found
    exit /b 1
)

echo   MSVC ARM64 lib: %MSVC_ARM64_LIB%
echo   SDK ARM64 ucrt: %WIN_SDK_ARM64_UCRT%
echo   SDK ARM64 um:   %WIN_SDK_ARM64_UM%

:: Change to Swift directory
pushd "%SWIFT_DIR%"

:: Build Swift package for ARM64 with explicit LIB path
echo Building Swift package for ARM64 (this may take a few minutes)...
set "ARM64_LIB=%MSVC_ARM64_LIB%;%WIN_SDK_ARM64_UCRT%;%WIN_SDK_ARM64_UM%"
cmd /c "set LIB=%ARM64_LIB% && swift build -c release --triple aarch64-unknown-windows-msvc"
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] Swift ARM64 cross-compilation failed
    echo.
    echo This is a known limitation. Options:
    echo   1. Build on native ARM64 Windows machine
    echo   2. Use GitHub Actions with windows-11-arm runner
    echo   3. Download pre-built ARM64 DLL from GitHub releases
    echo.
    popd
    exit /b 1
)

:: Copy DLL to ARM64 output directory
set "SWIFT_DLL_ARM64=%SWIFT_DIR%\.build\aarch64-unknown-windows-msvc\release\azookey-engine.dll"
if not exist "%SWIFT_DLL_ARM64%" (
    :: Try alternate path for native ARM64 build
    set "SWIFT_DLL_ARM64=%SWIFT_DIR%\.build\release\azookey-engine.dll"
)
if not exist "%SWIFT_DLL_ARM64%" (
    echo [ERROR] ARM64 azookey-engine.dll not found in build output
    popd
    exit /b 1
)

copy /y "%SWIFT_DLL_ARM64%" "%OUTPUT_DIR%\azookey-engine.dll" >nul
echo Copied: azookey-engine.dll (ARM64)

:: Note about Swift Runtime DLLs
echo [INFO] Swift ARM64 runtime DLLs need to be obtained from ARM64 Swift installation
echo        or downloaded from GitHub Actions artifacts

popd

echo Swift ARM64 DLL build completed.
echo.

:: ==============================================
:: Step 3: Copy llama.cpp dependencies
:: ==============================================
echo [Step 3/4] Copying llama.cpp ARM64 dependencies...
echo.

set "LLAMA_BUILD_ARM64=%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows-arm64"
if exist "%LLAMA_BUILD_ARM64%" (
    echo Copying ARM64 llama.cpp DLLs...
    for %%f in (ggml.dll ggml-base.dll ggml-cpu.dll llama.dll) do (
        if exist "%LLAMA_BUILD_ARM64%\%%f" (
            copy /y "%LLAMA_BUILD_ARM64%\%%f" "%OUTPUT_DIR%\" >nul
            echo   Copied: %%f
        )
    )
) else (
    echo [WARNING] llama.cpp ARM64 build directory not found
)

echo.

:: ==============================================
:: Step 4: Build Mozc with Bazel
:: ==============================================
echo [Step 4/4] Building Mozc with Bazel for ARM64...
echo.

pushd "%MOZC_SRC%"

:: Check and build Qt if needed
if not exist "third_party\qt\bin\Qt6Core.dll" (
    echo Qt not found, running build_qt.py...
    python build_tools\build_qt.py --release --confirm_license
    if !ERRORLEVEL! NEQ 0 (
        echo [ERROR] Qt build failed
        popd
        exit /b 1
    )
)

:: Run update_deps.py if needed
echo Checking dependencies...
python build_tools\update_deps.py --noqt --nollvm --nomsys2 --nondk --nosubmodules

:: Build ARM64 MSI installer with Bazel
echo.
echo Building ARM64 MSI installer with Bazel (this may take several minutes)...
bazelisk build --config=oss_windows //win32/installer:installer_arm64
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Bazel ARM64 build failed
    popd
    exit /b 1
)

:: Copy MSI to root
set "MSI_PATH=%MOZC_SRC%\bazel-bin\win32\installer\Mozc_ARM64.msi"
if exist "%MSI_PATH%" (
    copy /y "%MSI_PATH%" "%ROOT_DIR%Mozc_ARM64.msi" >nul
    echo.
    echo ARM64 MSI installer created: %ROOT_DIR%Mozc_ARM64.msi
)

popd

echo.
echo ==============================================
echo Build completed successfully!
echo ==============================================
echo.
echo Output files:
echo   DLL: %OUTPUT_DIR%\azookey-engine.dll
echo   MSI: %ROOT_DIR%Mozc_ARM64.msi
echo.
echo To install the IME:
echo   1. Uninstall any existing Mozc/MyIME
echo   2. Run Mozc_ARM64.msi as administrator
echo   3. Restart your computer
echo.

endlocal
exit /b 0
