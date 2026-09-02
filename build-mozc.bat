@echo off
call "%~dp0build-x64.bat" --mozc-only
exit /b %ERRORLEVEL%
