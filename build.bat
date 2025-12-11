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
::
:: Usage:
::   build.bat              - Build x64 and ARM64
::   build.bat --no-arm64   - Build x64 only (skip ARM64)
:: ==============================================

set "ROOT_DIR=%~dp0"
set "SWIFT_DIR=%ROOT_DIR%src\swift-engine"
set "MOZC_SRC=%ROOT_DIR%mozc\src"
set "BUILD_DIR=%ROOT_DIR%build"
set "OUTPUT_DIR=%BUILD_DIR%\x64\release"
set "OUTPUT_DIR_ARM64=%BUILD_DIR%\arm64\release"

:: Parse command line arguments
set "BUILD_ARM64=1"
for %%a in (%*) do (
    if /i "%%a"=="--no-arm64" set "BUILD_ARM64=0"
)

echo ==============================================
echo MyIME Build Script (Bazel)
echo ==============================================
if "%BUILD_ARM64%"=="1" (
    echo Build targets: x64 + ARM64
) else (
    echo Build targets: x64 only
)
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
            :: Check x64 compiler
            if exist "!MSVC_PATH!\bin\Hostx64\x64\cl.exe" (
                echo   [OK] x64 compiler found
            ) else (
                echo   [ERROR] x64 compiler not found
                echo   Please install "MSVC v143 - VS 2022 C++ x64/x86 build tools" via Visual Studio Installer
                set "DEPS_OK=0"
            )

            :: Check ARM64 cross-compiler (if ARM64 build enabled)
            if "!BUILD_ARM64!"=="1" (
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
                    echo   Or run with --no-arm64 to skip ARM64 build
                    set "DEPS_OK=0"
                )
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

:: Check Swift Runtime DLLs
echo.
echo Checking Swift Runtime...
set "SWIFT_RUNTIME_FOUND="
for %%p in ("%LocalAppData%\Programs\Swift\Runtimes" "%ProgramFiles%\Swift\Runtimes" "%SystemDrive%\Library\Swift\Runtimes") do (
    if exist "%%~p" (
        for /d %%t in ("%%~p\*") do (
            if exist "%%t\usr\bin\swiftCore.dll" (
                set "SWIFT_RUNTIME_FOUND=%%t\usr\bin"
                goto :swift_runtime_check_done
            )
        )
    )
)
:swift_runtime_check_done
if defined SWIFT_RUNTIME_FOUND (
    echo   [OK] Swift Runtime found at: %SWIFT_RUNTIME_FOUND%
) else (
    echo   [ERROR] Swift Runtime DLLs not found
    echo   Please ensure Swift is properly installed with runtime libraries
    set "DEPS_OK=0"
)

:: Check llama.cpp dependencies for Zenzai (x64)
echo.
echo Checking llama.cpp dependencies...
set "LLAMA_BUILD=%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows"
if exist "%LLAMA_BUILD%\ggml.dll" (
    echo   [OK] llama.cpp x64 DLLs found
) else (
    echo   [WARNING] llama.cpp x64 DLLs not found at %LLAMA_BUILD%
    echo   Zenzai AI acceleration will not work without these.
)

:: Check llama.cpp dependencies for ARM64 (if ARM64 build enabled)
if "%BUILD_ARM64%"=="1" (
    set "LLAMA_BUILD_ARM64=%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows-arm64"
    if exist "!LLAMA_BUILD_ARM64!\ggml.dll" (
        echo   [OK] llama.cpp ARM64 DLLs found
    ) else (
        echo   [WARNING] llama.cpp ARM64 DLLs not found at !LLAMA_BUILD_ARM64!
        echo   Run build-llama-arm64.bat to build ARM64 llama.cpp DLLs.
    )
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

echo Swift x64 DLL build completed.

:: Build ARM64 Swift DLL (if ARM64 build enabled)
if "%BUILD_ARM64%"=="1" call :build_swift_arm64
echo.

:: ==============================================
:: Step 3: Copy llama.cpp dependencies
:: ==============================================
echo [Step 3/4] Copying llama.cpp dependencies...
echo.

set "LLAMA_BUILD=%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows"
if exist "%LLAMA_BUILD%" (
    echo Copying x64 llama.cpp DLLs...
    for %%f in (ggml.dll ggml-base.dll ggml-cpu.dll ggml-vulkan.dll llama.dll llava_shared.dll mtmd.dll) do (
        if exist "%LLAMA_BUILD%\%%f" (
            copy /y "%LLAMA_BUILD%\%%f" "%OUTPUT_DIR%\" >nul
            echo   Copied: %%f
        )
    )
) else (
    echo [WARNING] llama.cpp x64 build directory not found
)

:: Copy ARM64 llama.cpp DLLs (if ARM64 build enabled)
if "%BUILD_ARM64%"=="1" (
    set "LLAMA_BUILD_ARM64=%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows-arm64"
    if exist "!LLAMA_BUILD_ARM64!" (
        echo Copying ARM64 llama.cpp DLLs...
        for %%f in (ggml.dll ggml-base.dll ggml-cpu.dll llama.dll) do (
            if exist "!LLAMA_BUILD_ARM64!\%%f" (
                copy /y "!LLAMA_BUILD_ARM64!\%%f" "%OUTPUT_DIR_ARM64%\" >nul
                echo   Copied: %%f ^(ARM64^)
            )
        )
    ) else (
        echo [WARNING] llama.cpp ARM64 build directory not found
    )
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

:: Build MSI installer with Bazel (x64)
echo.
echo Building x64 MSI installer with Bazel (this may take several minutes)...
bazelisk build --config=oss_windows //win32/installer:installer_x64
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Bazel x64 build failed
    popd
    exit /b 1
)

:: Copy x64 MSI to root
set "MSI_PATH_X64=%MOZC_SRC%\bazel-bin\win32\installer\Mozc_x64.msi"
if exist "%MSI_PATH_X64%" (
    copy /y "%MSI_PATH_X64%" "%ROOT_DIR%Mozc_x64.msi" >nul
    echo.
    echo x64 MSI installer created: %ROOT_DIR%Mozc_x64.msi
)

:: Build ARM64 MSI installer (if ARM64 build enabled)
if "%BUILD_ARM64%"=="1" (
    echo.
    echo Building ARM64 MSI installer with Bazel...
    bazelisk build --config=oss_windows //win32/installer:installer_arm64
    if !ERRORLEVEL! NEQ 0 (
        echo [WARNING] Bazel ARM64 build failed - ARM64 MSI will not be available
        echo ARM64 DLLs are still available in: %OUTPUT_DIR_ARM64%
    ) else (
        set "MSI_PATH_ARM64=%MOZC_SRC%\bazel-bin\win32\installer\Mozc_ARM64.msi"
        if exist "!MSI_PATH_ARM64!" (
            copy /y "!MSI_PATH_ARM64!" "%ROOT_DIR%Mozc_ARM64.msi" >nul
            echo.
            echo ARM64 MSI installer created: %ROOT_DIR%Mozc_ARM64.msi
        )
    )
)

popd

echo.
echo ==============================================
echo Build completed successfully!
echo ==============================================
echo.
echo Output files:
echo   x64 DLL: %OUTPUT_DIR%\azookey-engine.dll
if "%BUILD_ARM64%"=="1" (
    echo   ARM64 DLL: %OUTPUT_DIR_ARM64%\azookey-engine.dll
)
echo   x64 MSI: %ROOT_DIR%Mozc_x64.msi
if "%BUILD_ARM64%"=="1" (
    if exist "%ROOT_DIR%Mozc_ARM64.msi" (
        echo   ARM64 MSI: %ROOT_DIR%Mozc_ARM64.msi
    )
)
echo.
echo To install the IME:
echo   1. Uninstall any existing Mozc/MyIME
echo   2. Run Mozc_x64.msi as administrator
echo   3. Restart your computer
echo.

endlocal
exit /b 0

:: ==============================================
:: Subroutine: Build Swift ARM64 DLL
:: ==============================================
:build_swift_arm64
setlocal EnableDelayedExpansion
echo.
echo Building Swift ARM64 DLL...

:: Create ARM64 output directory
if not exist "%OUTPUT_DIR_ARM64%" mkdir "%OUTPUT_DIR_ARM64%"

:: Setup ARM64 Visual Studio environment for cross-compilation (in a new process)
echo Setting up ARM64 cross-compilation environment...

:: Change to Swift directory
pushd "%SWIFT_DIR%"

:: Build Swift package for ARM64 using cmd /c to isolate environment
echo Building Swift package for ARM64 (this may take a few minutes)...
cmd /c "call "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" x64_arm64 >nul 2>&1 && swift build -c release --triple aarch64-unknown-windows-msvc"
if !ERRORLEVEL! NEQ 0 (
    echo [WARNING] Swift ARM64 build failed - ARM64 MSI will not include Swift DLL
    popd
    endlocal
    goto :eof
)

:: Copy DLL to ARM64 output directory
:: Note: Cross-compilation outputs to .build\aarch64-unknown-windows-msvc\release
set "SWIFT_DLL_ARM64=%SWIFT_DIR%\.build\aarch64-unknown-windows-msvc\release\azookey-engine.dll"
if not exist "!SWIFT_DLL_ARM64!" (
    :: Try alternate path for native ARM64 build
    set "SWIFT_DLL_ARM64=%SWIFT_DIR%\.build\release\azookey-engine.dll"
)
if not exist "!SWIFT_DLL_ARM64!" (
    echo [WARNING] ARM64 azookey-engine.dll not found in build output
    echo   Tried: %SWIFT_DIR%\.build\aarch64-unknown-windows-msvc\release\azookey-engine.dll
    echo   Tried: %SWIFT_DIR%\.build\release\azookey-engine.dll
    popd
    endlocal
    goto :eof
)

copy /y "!SWIFT_DLL_ARM64!" "%OUTPUT_DIR_ARM64%\azookey-engine.dll" >nul
echo Copied: azookey-engine.dll (ARM64)

:: Note: Swift Runtime DLLs for ARM64 need to be obtained separately
:: The x64 runtime DLLs are not compatible with ARM64
echo [INFO] Swift ARM64 runtime DLLs need to be obtained from ARM64 Swift installation
echo        Skipping Swift runtime copy for ARM64

popd
endlocal
echo Swift ARM64 DLL build completed.
goto :eof

