@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d C:\Users\unok\git\myime\tests
cl.exe /nologo /EHsc /O2 /Fe:check_deps.exe check_deps.cpp
C:\Users\unok\git\myime\tests\check_deps.exe
