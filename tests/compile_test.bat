@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
cd /d "%~dp0"
cl.exe /nologo /EHsc /O2 /Fe:zenzai_test.exe zenzai_test.cpp
if exist zenzai_test.exe (
    echo Compilation successful
) else (
    echo Compilation failed
)
