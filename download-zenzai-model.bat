@echo off
setlocal

echo ==============================================
echo Downloading Zenzai Model for MyIME
echo ==============================================
echo.

set "ROOT_DIR=%~dp0"
set "MODEL_DIR=%ROOT_DIR%models"
set "MODEL_URL=https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf?download=true"
set "MODEL_FILE=%MODEL_DIR%\ggml-model-Q5_K_M.gguf"

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
echo Downloading Zenzai v3-small model...
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
echo 2. Run test-ime.bat to test AI conversion
echo.

pause
endlocal