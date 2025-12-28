@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d C:\Users\unok\git\myime\tests
cl.exe /nologo /EHsc /O2 /Fe:zenzai_test.exe zenzai_test.cpp > compile.log 2>&1
type compile.log
if exist C:\Users\unok\git\myime\tests\zenzai_test.exe (
    echo.
    echo === Running Test ===
    echo.
    C:\Users\unok\git\myime\tests\zenzai_test.exe
) else (
    echo Compilation failed. See compile.log for details.
)
