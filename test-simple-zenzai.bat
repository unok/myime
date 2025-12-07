@echo off
setlocal enabledelayedexpansion

echo === Simple Zenzai Test ===
echo.

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

:: Check model file
echo [Model File Check]
if exist "models\ggml-model-Q5_K_M.gguf" (
    for %%F in ("models\ggml-model-Q5_K_M.gguf") do echo Model size: %%~zF bytes
) else (
    echo Model not found!
)
echo.

:: Run test with logging
echo [Running IME Test]
echo Testing with Zenzai enabled...
echo.

cd test\bin\Release\net8.0
TestIme.exe

echo.
echo Test completed.
pause