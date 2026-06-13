@echo off
setlocal EnableDelayedExpansion

:: ==============================================
:: MyIME 開発用 再インストール (再起動不要)
:: ==============================================
:: 既存 Mozc を完全アンインストールしてからクリーン新規インストールする。
:: 初回インストールでは RegisterTIP64 + EnableTipProfile が確実に走るため、
:: TIP(テキストサービス)が登録され IME 一覧に出る。
:: 非Release ビルドには ScheduleReboot が無いので、プロセス/サービスを止めれば
:: マシン再起動なしで何度でも入れ直せる。
::
:: 使い方:  dev-reinstall.bat            (既定の MSI を使用)
::          dev-reinstall.bat "msiパス"  (MSI を明示指定)
::
:: 注意: mozc_tip64.dll を読み込み済みの一般アプリ(エクスプローラ/ブラウザ等)が
::       起動したままだと、その DLL だけ「使用中」で置換できないことがある。
::       その場合は該当アプリを閉じること。
:: ==============================================

set "ROOT_DIR=%~dp0"
set "UPGRADE_CODE={DD94B570-B5E2-4100-9D42-61930C611D8A}"

:: --- 管理者権限へ自己昇格 (msiexec とサービス操作に必要) ---
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo 管理者権限が必要です。昇格します...
    if "%~1"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
    )
    exit /b
)

:: --- MSI パス決定 ---
set "MSI=%~1"
if "%MSI%"=="" set "MSI=%ROOT_DIR%mozc\src\bazel-bin\win32\installer\Mozc_x64.msi"
if not exist "%MSI%" set "MSI=%ROOT_DIR%Mozc_x64.msi"
if not exist "%MSI%" (
    echo [ERROR] MSI が見つかりません: %MSI%
    echo   先に build-x64.bat を実行してください。
    pause
    exit /b 1
)
echo 使用する MSI: %MSI%

:: bazel-bin はシンボリックリンクで、その先は読み取り専用の Bazel キャッシュ。
:: Windows Installer サービス(SYSTEM)がリンク経由だと開けず error 1619 になるため、
:: 実体ファイルとして安定した場所へコピーしてからインストールする。
set "MSI_LOCAL=%SystemRoot%\Temp\Mozc_x64_dev.msi"
copy /y "%MSI%" "%MSI_LOCAL%" >nul 2>&1
if not exist "%MSI_LOCAL%" (
    echo [ERROR] MSI のコピーに失敗しました: %MSI_LOCAL%
    pause
    exit /b 1
)
echo インストール元: %MSI_LOCAL%
echo.

:: --- IME サービス/プロセスを停止してファイルロックを解放 ---
echo IME サービス/プロセスを停止しています...
sc stop MozcCacheService >nul 2>&1
taskkill /f /im mozc_server.exe        >nul 2>&1
taskkill /f /im mozc_renderer.exe      >nul 2>&1
taskkill /f /im mozc_broker.exe        >nul 2>&1
taskkill /f /im mozc_cache_service.exe >nul 2>&1
taskkill /f /im mozc_tool.exe          >nul 2>&1
taskkill /f /im ctfmon.exe             >nul 2>&1
ping -n 3 127.0.0.1 >nul

:: --- 既存 Mozc を UpgradeCode で検出して完全アンインストール ---
:: WiX は毎ビルドで ProductCode を再生成するため、ProductCode 指定では消せない。
:: UpgradeCode から関連製品を列挙して /x する。
echo 既存の Mozc をアンインストールしています...
powershell -NoProfile -Command "$i=New-Object -ComObject WindowsInstaller.Installer; try{$r=@($i.RelatedProducts('%UPGRADE_CODE%'))}catch{$r=@()}; foreach($p in $r){ Write-Host ('  uninstall: '+$p); $proc=Start-Process msiexec -ArgumentList ('/x '+$p+' /qn') -Wait -PassThru; Write-Host ('  exit='+$proc.ExitCode) }"
ping -n 2 127.0.0.1 >nul

:: --- クリーン新規インストール (RegisterTIP64 + EnableTipProfile が走る) ---
echo クリーン新規インストールしています...
msiexec /i "%MSI_LOCAL%" /qb
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" if not "%RC%"=="3010" (
    echo [ERROR] msiexec が失敗しました (exit %RC%)
    pause
    exit /b %RC%
)

:: --- IPC キャッシュ掃除 & テキストサービス再起動 ---
echo IME を再起動しています...
del /q "%USERPROFILE%\AppData\LocalLow\Mozc\*.ipc" >nul 2>&1
start "" ctfmon.exe

echo.
echo ==============================================
echo 完了しました (再起動不要)。
echo   IME 一覧 (Win+Space など) に Mozc が出るか確認してください。
echo ==============================================
ping -n 3 127.0.0.1 >nul
endlocal
