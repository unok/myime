@echo off
echo Restarting IME service...
taskkill /f /im mozc_server.exe 2>nul
taskkill /f /im mozc_renderer.exe 2>nul
taskkill /f /im mozc_cache_service.exe 2>nul
taskkill /f /im mozc_broker.exe 2>nul
taskkill /f /im ctfmon.exe 2>nul
timeout /t 1 /nobreak >nul
echo Deleting IPC files...
del /q C:\Users\unok\AppData\LocalLow\Mozc\*.ipc 2>nul
start ctfmon.exe
echo Done.
