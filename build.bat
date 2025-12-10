@echo off
setlocal EnableDelayedExpansion

:: ==============================================
:: MyIME Build Script (Bazel version)
:: ==============================================
:: This script builds the entire project from scratch:
:: 1. Check dependencies
:: 2. Build Swift DLL
:: 3. Copy llama.cpp dependencies
:: 4. Build Mozc with Bazel (includes MSI installer)
:: ==============================================

set "ROOT_DIR=%~dp0"
set "SWIFT_DIR=%ROOT_DIR%src\swift-engine"
set "MOZC_SRC=%ROOT_DIR%mozc\src"
set "BUILD_DIR=%ROOT_DIR%build"
set "OUTPUT_DIR=%BUILD_DIR%\x64\release"

echo ==============================================
echo MyIME Build Script (Bazel)
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
    echo   Please install Python 3.x
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
    echo   Please install Bazelisk from:
    echo   https://github.com/bazelbuild/bazelisk/releases
    echo   Or via: choco install bazelisk
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

:: Check llama.cpp dependencies for Zenzai
echo.
echo Checking llama.cpp dependencies...
set "LLAMA_BUILD=%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows"
if exist "%LLAMA_BUILD%\ggml.dll" (
    echo   [OK] llama.cpp DLLs found
) else (
    echo   [WARNING] llama.cpp DLLs not found at %LLAMA_BUILD%
    echo   Zenzai AI acceleration will not work without these.
)

:: Check Qt for Bazel
echo.
echo Checking Qt for Bazel...
if exist "%MOZC_SRC%\third_party\qt\bin\Qt6Core.dll" (
    echo   [OK] Qt found in third_party/qt
) else (
    echo   [INFO] Qt not found, will be built via build_qt.py
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
echo [Step 2/4] Building Swift DLL...
echo.

:: Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: Setup Visual Studio environment
echo Setting up Visual Studio environment...
call "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul 2>&1

:: Change to Swift directory
pushd "%SWIFT_DIR%"

:: Use local package configuration (with patched AzooKey)
if exist "Package-local.swift" (
    echo Using Package-local.swift...
    copy /y Package-local.swift Package.swift >nul
)

:: Build Swift package
echo Building Swift package (this may take a few minutes)...
swift build -c release --arch x86_64
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Swift build failed
    popd
    exit /b 1
)

:: Copy DLL to output directory
set "SWIFT_DLL=%SWIFT_DIR%\.build\release\azookey-engine.dll"
if not exist "%SWIFT_DLL%" (
    echo [ERROR] azookey-engine.dll not found in build output
    popd
    exit /b 1
)

copy /y "%SWIFT_DLL%" "%OUTPUT_DIR%\azookey-engine.dll" >nul
echo Copied: azookey-engine.dll

:: Copy Swift runtime libraries
:: Note: Swift Runtime DLLs are in "Runtimes" directory, NOT "Toolchains"
set "SWIFT_RUNTIME="
for %%p in ("%LocalAppData%\Programs\Swift\Runtimes" "%ProgramFiles%\Swift\Runtimes" "%SystemDrive%\Library\Swift\Runtimes") do (
    if exist "%%~p" (
        for /d %%t in ("%%~p\*") do (
            if exist "%%t\usr\bin\swiftCore.dll" (
                set "SWIFT_RUNTIME=%%t\usr\bin"
                goto :swift_runtime_found
            )
        )
    )
)
:swift_runtime_found
if defined SWIFT_RUNTIME (
    echo Copying Swift runtime libraries from: %SWIFT_RUNTIME%
    copy /y "%SWIFT_RUNTIME%\swiftCore.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\swiftCRT.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\swiftDispatch.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\swift_Concurrency.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\swiftWinSDK.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\Foundation.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\FoundationEssentials.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\FoundationInternationalization.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\_FoundationICU.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\BlocksRuntime.dll" "%OUTPUT_DIR%\" >nul 2>&1
    copy /y "%SWIFT_RUNTIME%\dispatch.dll" "%OUTPUT_DIR%\" >nul 2>&1
    echo   Copied Swift runtime DLLs
) else (
    echo [WARNING] Swift runtime not found - DLLs may be missing
)

popd

echo Swift DLL build completed.
echo.

:: ==============================================
:: Step 3: Copy llama.cpp dependencies
:: ==============================================
echo [Step 3/4] Copying llama.cpp dependencies...
echo.

set "LLAMA_BUILD=%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows"
if exist "%LLAMA_BUILD%" (
    for %%f in (ggml.dll ggml-base.dll ggml-cpu.dll ggml-vulkan.dll llama.dll llava_shared.dll mtmd.dll) do (
        if exist "%LLAMA_BUILD%\%%f" (
            copy /y "%LLAMA_BUILD%\%%f" "%OUTPUT_DIR%\" >nul
            echo Copied: %%f
        )
    )
) else (
    echo [WARNING] llama.cpp build directory not found
)

echo.

:: ==============================================
:: Step 4: Build Mozc with Bazel
:: ==============================================
echo [Step 4/4] Building Mozc with Bazel...
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

:: Run update_deps.py if needed (for WiX dotnet tool, etc.)
echo Checking dependencies...
python build_tools\update_deps.py --noqt --nollvm --nomsys2 --nondk --nosubmodules

:: Build MSI installer with Bazel
echo.
echo Building MSI installer with Bazel (this may take several minutes)...
bazelisk build --config=oss_windows //win32/installer:installer
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Bazel build failed
    popd
    exit /b 1
)

popd

:: Copy MSI to root
set "MSI_PATH=%MOZC_SRC%\bazel-bin\win32\installer\Mozc64.msi"
if exist "%MSI_PATH%" (
    copy /y "%MSI_PATH%" "%ROOT_DIR%Mozc64.msi" >nul
    echo.
    echo MSI installer created: %ROOT_DIR%Mozc64.msi
)

echo.
echo ==============================================
echo Build completed successfully!
echo ==============================================
echo.
echo Output files:
echo   DLL: %OUTPUT_DIR%\azookey-engine.dll
echo   MSI: %ROOT_DIR%Mozc64.msi
echo.
echo To install the IME:
echo   1. Uninstall any existing Mozc/MyIME
echo   2. Run Mozc64.msi as administrator
echo   3. Restart your computer
echo.

endlocal
exit /b 0
