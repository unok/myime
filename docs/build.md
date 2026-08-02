# ビルドガイド

MyIME のビルド環境の準備からインストール、開発時の再インストールまでをまとめる。機能や設定は [README](../README.md)、内部構造は [architecture.md](architecture.md) を参照。

## 必要環境

- Windows 10/11 (x64) ※ ARM64 は棚上げ中（[upstream-divergence.md](upstream-divergence.md) 参照）
- Visual Studio 2022（C++ ワークロード）
- Swift 6.2.1 以上（Windows 版）
- Bazelisk
- Python 3.x
- Windows SDK 10.0.22621.0 以上

Zenzai は既定で CPU 推論のため、ビルド・実行とも GPU は不要。GPU（Vulkan）切替を使う場合のみ Vulkan 対応 GPU とドライバが必要。

## ビルド手順

```cmd
git clone --recursive https://github.com/unok/myime.git
cd myime
build-x64.bat
```

成果物:

```
myime/
├── Mozc_x64.msi              # x64 インストーラ
└── build/x64/release/        # DLL 群（azookey-engine.dll ほか）
```

`build-x64.bat` は `MOZC_VERSION=3.33.<日数>.<UTC時分>` を注入するため、ビルドごとにバージョンが単調増加する。同じ MSI 名でも常に上書きインストールできる。

## スクリプト一覧

| スクリプト | 説明 |
|-----------|------|
| `build-x64.bat` | x64 用 Swift DLL + Mozc MSI をビルド |
| `build-x64-low.bat` | `build-x64.bat` を低優先度で実行（作業しながらビルドする用） |
| `build-mozc.bat` | Mozc のみビルド（Swift DLL はスキップ） |
| `build-arm64.bat` | ARM64 用ビルド（棚上げ中・動作しない） |
| `clean.bat` | ビルド成果物をクリーンアップ |
| `restart-ime.bat` | IME プロセスを再起動 |
| `dev-reinstall.bat` | 既存 Mozc を完全アンインストールしてからクリーン再インストール（開発用） |
| `download-zenzai-model.bat` | Zenzai モデルをリポジトリの `models/` へダウンロード |
| `setup-dictionaries.bat` | AzooKey 辞書サブモジュールの確認・配置 |
| `version_info.bat` | ビルド環境のツール・ライブラリのバージョンを表示 |

## インストールと開発時の再インストール

通常は `Mozc_x64.msi` を実行するだけでよい。開発中の入れ直しには `dev-reinstall.bat` を使う。上書きインストールには落とし穴が2つある。

- ビルド元が異なる MSI は上書きできないことがある。Windows Installer はバージョンの高い DLL を下げないため、CI 版（削減ビルドの Qt）とローカル版（公式 Qt）の混在は `mozc_tool.exe` のエントリポイントエラーを引き起こす。`dev-reinstall.bat` は完全アンインストール後に新規インストールするのでこの問題を回避できる
- IME の DLL（mozc_tip64.dll）は起動中の全 GUI アプリに読み込まれているため、アプリを多く開いたままだとインストールに数分かかる。閉じてから実行すれば15秒程度

インストール後の動作確認は必ず新しく開いたアプリで行う。起動済みアプリはプロセス再起動まで古い DLL を使い続ける。「要再起動」でインストールが終わった場合（イベントログ MsiInstaller 1038）は、再起動するまでディスク上も古い DLL のままになる。

## 部分ビルド・デバッグ

```cmd
cd mozc\src
bazelisk build --config=oss_windows //win32/installer:installer_x64
```

Swift エンジン単体のテスト（llama.cpp の DLL を PATH に入れないと無言で失敗する）:

```cmd
set PATH=%CD%\src\AzooKeyKanaKanjiConverter\lib\windows;%PATH%
cd src\swift-engine
swift test -c release
```

タイポ補正・辞書登録のヘッドレス検証手順は [architecture.md](architecture.md) の各節を参照。

## Mozc submodule の更新

```cmd
cd mozc
git pull origin patch-myime-next
cd ..
git add mozc
git commit -m "Update mozc submodule"
```

## CI

| ワークフロー | トリガー | 内容 |
|---|---|---|
| PR Tests | pull_request | Swift DLL ビルド + swift test + Bazel の主要ターゲットの build/test（MSI なし、約16分） |
| Build x64 | master への push / 手動実行 | フル MSI ビルド（成果物 `Mozc_x64` をダウンロード可能） |

ブランチを指定して MSI を作る場合:

```cmd
gh workflow run "Build x64" --ref <ブランチ名>
```

## トラブルシューティング

### Swift ビルドが失敗する

- Visual Studio 2022 の C++ ワークロードがインストールされているか確認
- Swift 6.2.1 以上がインストールされているか確認（`swift --version`）
- Swift Runtime が正しい場所にあるか確認（`%LOCALAPPDATA%\Programs\Swift\Runtimes\`）

### Bazel ビルドが失敗する

```cmd
cd mozc\src
bazelisk clean --expunge
```
