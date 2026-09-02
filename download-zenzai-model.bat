@echo off
setlocal

echo ==============================================
echo Downloading Zenzai Model for MyIME
echo ==============================================
echo.

set "ROOT_DIR=%~dp0"
set "MODEL_DIR=%ROOT_DIR%models"
set "MODEL_URL=https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/c67e03e07d215c869f591b274c1631170d3e11fe/ggml-model-Q5_K_M.gguf"
set "MODEL_FILE=%MODEL_DIR%\ggml-model-Q5_K_M.gguf"
set "MODEL_SHA256=29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673"

:: Create models directory
if not exist "%MODEL_DIR%" (
    echo Creating models directory...
    mkdir "%MODEL_DIR%"
)

:: Check if model already exists
if exist "%MODEL_FILE%" (
    echo Model already exists: %MODEL_FILE%
    echo.
    echo If you want to re-download, delete the existing file first.
    pause
    exit /b 0
)

:: Download using curl
echo Downloading zenz-v3.2-small model...
echo This may take a few minutes...
echo.

curl -L -o "%MODEL_FILE%" "%MODEL_URL%"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Failed to download model
    echo Please check your internet connection and try again.
    pause
    exit /b 1
)

:: Verify SHA256
echo Verifying SHA256...
certutil -hashfile "%MODEL_FILE%" SHA256 | findstr /i /c:"%MODEL_SHA256%" >nul
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: SHA256 verification failed
    del /q "%MODEL_FILE%" 2>nul
    pause
    exit /b 1
)

echo.
echo ==============================================
echo Download completed successfully!
echo ==============================================
echo.
echo Model saved to: %MODEL_FILE%
echo.
echo Next steps:
echo 1. Update config.json with:
echo    "zenzaiEnabled": true,
echo    "zenzaiWeightPath": "%MODEL_FILE:\=\\%"
echo 2. To use it in the IME, copy the file to %%LOCALAPPDATA%%\Mozc\models\
echo.

pause
endlocal
