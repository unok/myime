@echo off
echo Restarting IME service...
taskkill /f /im mozc_server.exe 2>nul
taskkill /f /im mozc_renderer.exe 2>nul
taskkill /f /im mozc_cache_service.exe 2>nul
taskkill /f /im mozc_broker.exe 2>nul
taskkill /f /im ctfmon.exe 2>nul
timeout /t 1 /nobreak >nul
start ctfmon.exe
echo Done.
pause
