@echo off
setlocal EnableDelayedExpansion

:: ==============================================
:: MyIME Version Info
:: ==============================================
:: ビルド環境のツール・ライブラリのバージョンを表示する
:: ==============================================

set "ROOT_DIR=%~dp0"
set "MOZC_SRC=%ROOT_DIR%mozc\src"

echo ==============================================
echo MyIME - Build Environment Version Info
echo ==============================================
echo.

:: ==============================================
:: System Tools
:: ==============================================
echo [System Tools]
echo ----------------------------------------------

:: Git
where git >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   Git:            NOT FOUND
) else (
    for /f "tokens=*" %%v in ('git --version 2^>^&1') do echo   Git:            %%v
)

:: Swift
where swift >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   Swift:          NOT FOUND
) else (
    for /f "tokens=*" %%v in ('swift --version 2^>^&1 ^| findstr /R "Swift version"') do echo   Swift:          %%v
)

:: Python
where python >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   Python:         NOT FOUND
) else (
    for /f "tokens=*" %%v in ('python --version 2^>^&1') do echo   Python:         %%v
)

:: Bazelisk
where bazelisk >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   Bazelisk:       NOT FOUND
) else (
    echo   Bazelisk:       Found
    for /f "tokens=3" %%v in ('bazelisk version 2^>^&1 ^| findstr /C:"Build label:"') do echo   Bazel Version:  %%v
)

:: LLVM/Clang
set "CLANG_INFO="
if exist "C:\Program Files\LLVM\bin\clang-cl.exe" (
    "C:\Program Files\LLVM\bin\clang-cl.exe" --version > "%TEMP%\myime_clang_ver.txt" 2>&1
    for /f "tokens=*" %%v in ('findstr /R "clang version" "%TEMP%\myime_clang_ver.txt"') do set "CLANG_INFO=%%v"
    del "%TEMP%\myime_clang_ver.txt" >nul 2>&1
)
if not defined CLANG_INFO (
    where clang-cl >nul 2>&1
    if !ERRORLEVEL! NEQ 0 (
        set "CLANG_INFO=NOT FOUND"
    ) else (
        for /f "tokens=*" %%v in ('clang-cl --version 2^>^&1 ^| findstr /R "clang version"') do set "CLANG_INFO=%%v"
    )
)
echo   Clang:          !CLANG_INFO!

:: .NET
where dotnet >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   .NET:           NOT FOUND
) else (
    for /f "tokens=*" %%v in ('dotnet --version 2^>^&1') do echo   .NET SDK:       %%v
)

echo.

:: ==============================================
:: Visual Studio / MSVC
:: ==============================================
echo [Visual Studio / MSVC]
echo ----------------------------------------------

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo   Visual Studio:  NOT FOUND (vswhere.exe not found)
) else (
    for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -property displayName 2^>nul`) do (
        echo   Edition:        %%i
    )
    for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -property installationVersion 2^>nul`) do (
        echo   VS Version:     %%i
    )
    for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do (
        set "VS_PATH=%%i"
    )
    if defined VS_PATH (
        REM Find MSVC version
        set "MSVC_VER="
        for /d %%v in ("!VS_PATH!\VC\Tools\MSVC\*") do set "MSVC_VER=%%~nxv"
        if defined MSVC_VER (
            echo   MSVC Version:   !MSVC_VER!
        ) else (
            echo   MSVC Version:   NOT FOUND
        )
    )
)

echo.

:: ==============================================
:: Windows SDK
:: ==============================================
echo [Windows SDK]
echo ----------------------------------------------

set "WIN_SDK_FOUND="
for %%v in (10.0.26220.0 10.0.22621.0 10.0.22000.0 10.0.19041.0 10.0.18362.0 10.0.17763.0) do (
    if not defined WIN_SDK_FOUND (
        if exist "%ProgramFiles(x86)%\Windows Kits\10\Include\%%v\ucrt" (
            echo   Windows SDK:    %%v
            set "WIN_SDK_FOUND=1"
        )
    )
)
if not defined WIN_SDK_FOUND (
    echo   Windows SDK:    NOT FOUND
)

echo.

:: ==============================================
:: Swift Runtime
:: ==============================================
echo [Swift Runtime]
echo ----------------------------------------------

set "SWIFT_RUNTIME_FOUND="
for %%p in ("%LocalAppData%\Programs\Swift\Runtimes" "%ProgramFiles%\Swift\Runtimes" "%SystemDrive%\Library\Swift\Runtimes") do (
    if not defined SWIFT_RUNTIME_FOUND (
        if exist "%%~p" (
            for /d %%t in ("%%~p\*") do (
                if exist "%%t\usr\bin\swiftCore.dll" (
                    set "SWIFT_RUNTIME_FOUND=%%t\usr\bin"
                    echo   Path:           !SWIFT_RUNTIME_FOUND!
                    echo   Runtime DLLs:
                    for %%d in (swiftCore.dll swiftCRT.dll swiftDispatch.dll swift_Concurrency.dll swiftWinSDK.dll Foundation.dll FoundationEssentials.dll FoundationInternationalization.dll _FoundationICU.dll BlocksRuntime.dll dispatch.dll) do (
                        if exist "!SWIFT_RUNTIME_FOUND!\%%d" (
                            echo     [OK] %%d
                        ) else (
                            echo     [--] %%d
                        )
                    )
                )
            )
        )
    )
)
if not defined SWIFT_RUNTIME_FOUND (
    echo   Swift Runtime:  NOT FOUND
)

echo.

:: ==============================================
:: Qt (Mozc UI)
:: ==============================================
echo [Qt]
echo ----------------------------------------------

if exist "%MOZC_SRC%\third_party\qt\bin\Qt6Core.dll" (
    echo   Qt6Core.dll:    Found
    echo   Path:           %MOZC_SRC%\third_party\qt
    REM Try to get Qt version from qmake
    if exist "%MOZC_SRC%\third_party\qt\bin\qmake6.exe" (
        for /f "tokens=*" %%v in ('"%MOZC_SRC%\third_party\qt\bin\qmake6.exe" -query QT_VERSION 2^>^&1') do echo   Qt Version:     %%v
    )
) else (
    echo   Qt:             NOT FOUND (run build script to download)
)

echo.

:: ==============================================
:: WiX Toolset
:: ==============================================
echo [WiX Toolset]
echo ----------------------------------------------

set "WIX_FOUND="
where wix >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    for /f "tokens=*" %%v in ('wix --version 2^>^&1') do (
        echo   WiX Version:    %%v
        set "WIX_FOUND=1"
    )
)
if not defined WIX_FOUND (
    dotnet tool list -g > "%TEMP%\myime_dotnet_tools.txt" 2>nul
    for /f "tokens=1,2" %%a in ('findstr /i "wix" "%TEMP%\myime_dotnet_tools.txt" 2^>nul') do (
        echo   WiX ^(dotnet^):   %%b
        set "WIX_FOUND=1"
    )
    del "%TEMP%\myime_dotnet_tools.txt" >nul 2>&1
)
if not defined WIX_FOUND echo   WiX Toolset:    NOT FOUND
echo   Required:       5.0.2 (MODULE.bazel)

echo.

:: ==============================================
:: llama.cpp DLLs
:: ==============================================
echo [llama.cpp DLLs]
echo ----------------------------------------------

set "LLAMA_DIR=%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows"
if exist "%LLAMA_DIR%" (
    echo   Path: %LLAMA_DIR%
    for %%f in (ggml.dll ggml-base.dll ggml-cpu.dll ggml-vulkan.dll llama.dll) do (
        if exist "%LLAMA_DIR%\%%f" (
            echo     [OK] %%f
        ) else (
            echo     [--] %%f
        )
    )
) else (
    echo   llama.cpp DLLs: NOT FOUND
)

echo.

:: ==============================================
:: Bazel Dependencies (from MODULE.bazel)
:: ==============================================
echo [Bazel Dependencies (MODULE.bazel)]
echo ----------------------------------------------

:: ハードコードすると MODULE.bazel 更新時に乖離して嘘をつくため、動的に抽出する
if exist "%~dp0mozc\src\MODULE.bazel" (
    powershell -NoProfile -Command "$t = Get-Content -Raw '%~dp0mozc\src\MODULE.bazel'; foreach ($m in [regex]::Matches($t, 'bazel_dep\(\s*name\s*=\s*\"([^\"]+)\"\s*,\s*version\s*=\s*\"([^\"]+)\"')) { '  {0,-20} {1}' -f ($m.Groups[1].Value + ':'), $m.Groups[2].Value }"
) else (
    echo   [N/A] mozc\src\MODULE.bazel not found - run: git submodule update --init
)

echo.

:: ==============================================
:: Git Repository Info
:: ==============================================
echo [Git Repository Info]
echo ----------------------------------------------

pushd "%ROOT_DIR%"

for /f "tokens=*" %%v in ('git rev-parse --abbrev-ref HEAD 2^>^&1') do echo   Branch:         %%v
for /f "tokens=*" %%v in ('git rev-parse --short HEAD 2^>^&1') do echo   Commit:         %%v
git log -1 --format=%%ci > "%TEMP%\myime_git_date.txt" 2>&1
set /p GIT_DATE=<"%TEMP%\myime_git_date.txt"
echo   Date:           !GIT_DATE!
del "%TEMP%\myime_git_date.txt" >nul 2>&1

echo.
echo   Submodules:
for /f "delims=" %%a in ('git submodule status 2^>nul') do (
    echo     %%a
)

popd

echo.
:: ==============================================
:: AzooKey Engine Status
:: ==============================================
echo [AzooKey Engine Status]
echo ----------------------------------------------

for %%v in (AzooKeyEngineState AzooKeyEngineError AzooKeyLearningActive AzooKeyLearningDisabledReason ZenzaiActive) do (
    reg query "HKCU\Software\Mozc" /v %%v >nul 2>&1
    if !ERRORLEVEL! NEQ 0 (
        echo   %%v: ^(not set^)
    ) else (
        set "REG_VALUE="
        for /f "tokens=1,2,*" %%a in ('reg query "HKCU\Software\Mozc" /v %%v 2^>nul ^| findstr /I /C:"%%v"') do set "REG_VALUE=%%c"
        echo   %%v: !REG_VALUE!
    )
)

echo.
echo ==============================================
echo Done.
echo ==============================================

endlocal
exit /b 0
