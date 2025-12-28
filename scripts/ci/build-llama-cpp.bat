@echo off
setlocal EnableDelayedExpansion

:: ============================================
:: Build llama.cpp with Vulkan support
:: Usage: build-llama-cpp.bat <arch> <version> <output_dir>
::   arch: x64 or ARM64
::   version: llama.cpp release tag (e.g., b4547)
::   output_dir: directory to copy DLLs to
:: ============================================

set "ARCH=%~1"
set "VERSION=%~2"
set "OUTPUT_DIR=%~3"

if "%ARCH%"=="" set "ARCH=x64"
if "%VERSION%"=="" set "VERSION=b4547"
if "%OUTPUT_DIR%"=="" set "OUTPUT_DIR=llama.cpp-build"

echo Building llama.cpp %VERSION% for %ARCH%...

:: Clone if not exists
if not exist "llama.cpp-src" (
    echo Cloning llama.cpp %VERSION%...
    git clone --depth 1 --branch %VERSION% https://github.com/ggerganov/llama.cpp.git llama.cpp-src
    if !ERRORLEVEL! NEQ 0 (
        echo [ERROR] Failed to clone llama.cpp
        exit /b 1
    )
)

:: Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: Set architecture for CMake
if /i "%ARCH%"=="x64" (
    set "CMAKE_ARCH=x64"
) else if /i "%ARCH%"=="arm64" (
    set "CMAKE_ARCH=ARM64"
) else (
    echo [ERROR] Unknown architecture: %ARCH%
    exit /b 1
)

:: Build
cd llama.cpp-src
echo Configuring CMake for %CMAKE_ARCH%...
cmake -B build -G "Visual Studio 17 2022" -A %CMAKE_ARCH% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DGGML_VULKAN=ON ^
    -DLLAMA_BUILD_TESTS=OFF ^
    -DLLAMA_BUILD_EXAMPLES=OFF ^
    -DLLAMA_BUILD_SERVER=OFF ^
    -DBUILD_SHARED_LIBS=ON

if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] CMake configuration failed
    cd ..
    exit /b 1
)

echo Building core libraries only (llama, ggml)...
cmake --build build --config Release --parallel --target llama ggml
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Build failed
    cd ..
    exit /b 1
)

:: Copy DLLs
echo Copying DLLs to %OUTPUT_DIR%...
copy /y build\bin\Release\*.dll "..\%OUTPUT_DIR%\" >nul 2>&1
copy /y build\bin\Release\*.lib "..\%OUTPUT_DIR%\" >nul 2>&1

cd ..
echo llama.cpp build completed successfully.
exit /b 0
