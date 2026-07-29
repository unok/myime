@echo off
setlocal EnableDelayedExpansion
cd /d %~dp0

echo === CI Build Started: %date% %time% ===
echo.

echo === Step 1: Create build directories ===
if not exist build\x64\release mkdir build\x64\release
echo Done
echo.

echo === Step 2: Build llama.cpp ===
call scripts\ci\build-llama-cpp.bat x64 "" llama.cpp-build
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] llama.cpp build failed
    exit /b 1
)
echo.

echo === Step 3: Copy llama.cpp DLLs ===
powershell -ExecutionPolicy Bypass -File scripts/ci/copy-llama-dlls.ps1 -Arch x64 -SourceDir llama.cpp-build
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] copy-llama-dlls failed
    exit /b 1
)
echo.

echo === Step 4: Build Swift DLL ===
cd src\swift-engine
swift build -c release --arch x86_64
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Swift build failed
    cd ..\..
    exit /b 1
)
copy /y .build\release\azookey-engine.dll ..\..\build\x64\release\
cd ..\..
echo.

echo === Step 5: Copy Swift Runtime DLLs ===
powershell -ExecutionPolicy Bypass -File scripts/ci/copy-swift-runtime.ps1 -OutputDir build/x64/release
echo.

echo === Step 6: Update Mozc dependencies ===
cd mozc\src
python build_tools/update_deps.py --noqt --nollvm --nomsys2 --nondk
echo.

echo === Step 7: Build Mozc x64 MSI ===
bazelisk build --config=oss_windows --spawn_strategy=local --action_env=__COMPAT_LAYER=RunAsInvoker //win32/installer:installer_x64
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Mozc build failed
    cd ..\..
    exit /b 1
)
cd ..\..
echo.

echo === Step 8: Copy MSI ===
copy mozc\src\bazel-bin\win32\installer\Mozc_x64.msi .
echo.

echo === CI Build Completed: %date% %time% ===
