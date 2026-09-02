@echo off
setlocal EnableDelayedExpansion

:: ============================================
:: Build llama.cpp (CPU + Vulkan module, dynamic loading; Vulkan unused by default)
:: Usage: build-llama-cpp.bat <arch> <version> <output_dir>
::   arch: x64 or ARM64
::   version: llama.cpp release tag (default: scripts/llama-cpp-version.env)
::   output_dir: directory to copy DLLs to
::
:: NOTE: This builds the pinned MyIME llama.cpp fork, not vanilla llama.cpp.
:: The fork carries the Zenzai tokenizer patch
:: (LLAMA_VOCAB_PRE_TYPE_GPT2_SMALL_JAPANESE_CHAR).
:: Repository and version are defined in scripts/llama-cpp-version.env.
::
:: Backend layout uses dynamic backend loading for CPU plus Vulkan module.
:: GGML_BACKEND_DL=ON detaches backend DLLs from ggml.dll. The app currently
:: loads ggml-cpu.dll explicitly; ggml-vulkan.dll is packaged but not loaded.
:: ============================================

set "ARCH=%~1"
set "VERSION=%~2"
set "OUTPUT_DIR=%~3"

:: Load pinned llama.cpp source (single source of truth)
for /f "usebackq tokens=1,* delims==" %%a in ("%~dp0..\llama-cpp-version.env") do set "%%a=%%b"

:: Some shells collapse an empty second argument; keep the documented call safe.
if "%OUTPUT_DIR%"=="" if /i "%VERSION%"=="llama.cpp-build" (
    set "OUTPUT_DIR=%VERSION%"
    set "VERSION="
)

if "%ARCH%"=="" set "ARCH=x64"
if "%VERSION%"=="" set "VERSION=%LLAMA_CPP_VERSION%"
if "%OUTPUT_DIR%"=="" set "OUTPUT_DIR=llama.cpp-build"

echo Building llama.cpp %VERSION% for %ARCH%...

:: Re-clone if existing checkout doesn't match the pinned repo+version
set "SOURCE_ID=%LLAMA_CPP_REPO% %VERSION%"
if exist "llama.cpp-src" (
    set "EXISTING_SOURCE="
    if exist "llama.cpp-src\.myime-llama-version" (
        set /p EXISTING_SOURCE=<"llama.cpp-src\.myime-llama-version"
    )
    if not "!EXISTING_SOURCE!"=="%SOURCE_ID%" (
        echo Existing llama.cpp-src is "!EXISTING_SOURCE!", want "%SOURCE_ID%". Re-cloning...
        rmdir /s /q llama.cpp-src
    )
)

:: Clone if not exists
if not exist "llama.cpp-src" (
    echo Cloning llama.cpp %VERSION% from %LLAMA_CPP_REPO%...
    git clone --depth 1 --branch %VERSION% %LLAMA_CPP_REPO% llama.cpp-src
    if !ERRORLEVEL! NEQ 0 (
        echo [ERROR] Failed to clone llama.cpp
        exit /b 1
    )
    echo %SOURCE_ID%>"llama.cpp-src\.myime-llama-version"
)

:: Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: Set architecture for CMake
if /i "%ARCH%"=="x64" (
    set "CMAKE_ARCH=x64"
    set "CMAKE_TOOLCHAIN="
    set "CMAKE_EXTRA_FLAGS="
) else if /i "%ARCH%"=="arm64" (
    set "CMAKE_ARCH=ARM64"
    :: ARM64 requires Clang toolchain (MSVC not supported for ARM in ggml-cpu)
    set "CMAKE_TOOLCHAIN=-T ClangCL"
    set "CMAKE_EXTRA_FLAGS=-DGGML_OPENMP=OFF"
) else (
    echo [ERROR] Unknown architecture: %ARCH%
    exit /b 1
)

:: Build
cd llama.cpp-src
echo Configuring CMake for %CMAKE_ARCH%...
cmake -B build -G "Visual Studio 17 2022" -A %CMAKE_ARCH% %CMAKE_TOOLCHAIN% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DGGML_VULKAN=ON ^
    -DGGML_BACKEND_DL=ON ^
    -DGGML_NATIVE=OFF ^
    -DGGML_AVX2=ON ^
    -DGGML_FMA=ON ^
    -DGGML_F16C=ON ^
    -DLLAMA_BUILD_TESTS=OFF ^
    -DLLAMA_BUILD_EXAMPLES=OFF ^
    -DLLAMA_BUILD_SERVER=OFF ^
    -DBUILD_SHARED_LIBS=ON ^
    %CMAKE_EXTRA_FLAGS%

if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] CMake configuration failed
    cd ..
    exit /b 1
)

echo Building core libraries (llama, ggml, ggml-base, ggml-cpu, ggml-vulkan)...
cmake --build build --config Release --parallel --target llama ggml ggml-base ggml-cpu ggml-vulkan
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Build failed
    cd ..
    exit /b 1
)

:: Copy DLLs and LIBs
echo Copying DLLs to %OUTPUT_DIR%...
copy /y build\bin\Release\*.dll "..\%OUTPUT_DIR%\" >nul 2>&1

:: .lib files - paths verified for b4846
echo Copying .lib files...
del /q "..\%OUTPUT_DIR%\ggml-cpu.lib" 2>nul
copy /y build\src\Release\llama.lib "..\%OUTPUT_DIR%\"
copy /y build\ggml\src\Release\ggml.lib "..\%OUTPUT_DIR%\"
copy /y build\ggml\src\Release\ggml-base.lib "..\%OUTPUT_DIR%\"

:: Show what was copied
echo Verifying copied files:
dir "..\%OUTPUT_DIR%\*.lib" 2>nul || echo No .lib files found
dir "..\%OUTPUT_DIR%\*.dll" 2>nul || echo No .dll files found

cd ..
echo llama.cpp build completed successfully.
exit /b 0
