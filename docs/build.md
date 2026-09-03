# ビルドガイド

MyIME のビルド環境の準備からインストール、開発時の再インストールまでをまとめる。機能や設定は [README](../README.md)、内部構造は [architecture.md](architecture.md) を参照。

## 必要環境

- Windows 10/11 (x64) ※ ARM64 は棚上げ中（[upstream-divergence.md](upstream-divergence.md) 参照）
- Visual Studio 2022（C++ ワークロード）
- Swift 6.3.3 以上（Windows 版）
- Bazelisk
- Python 3.x
- Windows SDK 10.0.22621.0 以上

Swift は CI と同じ版を使用すること。Windows の Swift は ABI 安定性がないため、ビルドしたツールチェーンと同じ版のランタイム DLL を同梱する必要があり、`scripts/ci/copy-swift-runtime.ps1` がツールチェーン版に合わせて自動選択する。

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
| `build-mozc.bat` | `build-x64.bat --mozc-only` のラッパー。Swift DLL ビルドをスキップして Mozc の MSI だけをビルドする（`build\x64\release` にビルド済み DLL が必要） |
| `build-arm64.bat` | ARM64 用ビルド（棚上げ中・動作しない） |
| `clean.bat` | ビルド成果物をクリーンアップ |
| `restart-ime.bat` | IME プロセスを再起動 |
| `dev-reinstall.bat` | 既存 Mozc を完全アンインストールしてからクリーン再インストール（開発用） |
| `download-zenzai-model.bat` | Zenzai モデルをリポジトリの `models/` へダウンロード |
| `setup-dictionaries.bat` | AzooKey 辞書サブモジュールの確認・配置 |
| `version_info.bat` | ビルド環境のツール・ライブラリのバージョンを表示。DLL 一覧は `scripts/ci/copy-*.ps1` を参照 |

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

### Mozc のテストをエンジン DLL 有りで走らせる

bazel test はテスト実行体を runfiles ツリーから実行するため、`bazel-bin` に DLL を置いても `azookey-engine.dll` は見つからない。`--test_env=MYIME_HERMETIC_TEST=1` で `converter/engine_config.h` の hermetic test-mode を明示的に有効にし（レジストリと `%LOCALAPPDATA%` のモデル探索を無視、Zenzai は `MYIME_AZOOKEY_ZENZAI_WEIGHT`（GGUF の絶対パス）を渡した時だけ有効、学習データは `TEST_TMPDIR` 配下、レジストリへの書き戻しなし）、`--test_env=MYIME_AZOOKEY_DLL_DIR`（絶対パス。hermetic test-mode の時だけ有効。`converter/azookey_immutable_converter.cc` の `LoadDll` 参照）で `build\x64\release` を指す。判定キーを `TEST_TMPDIR` にしないのは、シェルの環境変数が TIP や mozc_server、設定ダイアログへ継承されて本番で誤発動するのを防ぐため。

CI（Build x64）と同じ、全件通る組み合わせ:

```cmd
cd mozc\src
bazelisk test --config=oss_windows --spawn_strategy=local --test_env=MYIME_HERMETIC_TEST=1 --test_env=MYIME_AZOOKEY_DLL_DIR=%CD%\..\..\build\x64\release //converter:azookey_candidate_parser_test //converter:azookey_user_dictionary_test //session:session_handler_test //session:session_test
```

upstream のシナリオテストは任意実行（現状は失敗が残る。下記）:

```cmd
bazelisk test --config=oss_windows --spawn_strategy=local --test_env=MYIME_HERMETIC_TEST=1 --test_env=MYIME_AZOOKEY_DLL_DIR=%CD%\..\..\build\x64\release //session:session_handler_scenario_test
```

Git Bash から実行する場合は `MSYS_NO_PATHCONV=1` を付けないと `//session:` が `/session:` に書き換わる。

2026-09-02 時点の実測: `session_test` は全件通過、`session_handler_scenario_test` は 66 合格 / 30 失敗（15 シナリオ）。失敗はすべて Mozc の辞書・文節分割を前提にした期待値（`宗号する`、`東京タワー`、`中ノ` の 3 文節など）で、AzooKey エンジンでは成り立たない。除外リスト化・myime 版シナリオ・CI 外のどれにするかは #51 のコメントで判断待ち。

### ローカルの Qt を CI と同じ削減ビルドに揃える

既存の `mozc\src\third_party\qt` ジャンクション（`C:\Qt\6.8.0\msvc2022_64` 向け）を削除してから、CI（`.github/workflows/build-x64.yml`）と同じ順序で Qt ソースの取得 → 削減ビルド → 他の依存更新を実行する。版数は `scripts/ci/download-qt.ps1` の既定値（6.9.1）と `mozc/src/build_tools/update_deps.py` の定義が一致している必要がある。初回は時間がかかる。

```cmd
rmdir mozc\src\third_party\qt
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ci\download-qt.ps1 -OutputDir mozc\src\third_party_cache
cd mozc\src
python build_tools\build_qt.py --release --confirm_license
python build_tools\update_deps.py --noqt --nollvm --nomsys2 --nondk
```

`build_qt.py` は `third_party_cache\qtbase-everywhere-src-6.9.1.tar.xz` を既定で読み、`third_party\qt` に削減 Qt を生成する。ジャンクション運用を続ける場合は、ローカル版 MSI と CI 版 MSI を混在させない（完全アンインストール後にインストールする）。

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
| PR Tests | pull_request | Swift DLL ビルド + swift test + Bazel の主要ターゲット（`azookey_candidate_parser_test` を含む DLL 非依存テスト）の build/test（MSI なし、実測 26〜37 分（2026-08）） |
| Build x64 | master への push / 手動実行 | フル MSI ビルド（成果物 `Mozc_x64` をダウンロード可能）。DLL ビルド後に swift test と Python 回帰テスト（`scripts/tests/typo_*.py`）、MSI ビルド後にエンジン DLL 有りの Mozc テスト（`session_test` / `session_handler_test` / `azookey_*_test`）を実行する（#51） |

`**.md`・`docs/**` だけの変更ではどちらも走らない。キャッシュの保存は master（Build x64）だけが行い、PR は復元のみ。PR 側でも保存すると 1GB 超の bazel-disk キャッシュが PR ごとに積み上がり、上限 10GB の LRU で Qt / llama のキャッシュが追い出されて master のビルドが 40分 → 1時間20分超に悪化する（2026-08-03 実測）。

ブランチを指定して MSI を作る場合:

```cmd
gh workflow run "Build x64" --ref <ブランチ名>
```

## トラブルシューティング

### Swift ビルドが失敗する

- Visual Studio 2022 の C++ ワークロードがインストールされているか確認
- Swift 6.3.3 以上がインストールされているか確認（`swift --version`）
- Swift Runtime が正しい場所にあるか確認（`%LOCALAPPDATA%\Programs\Swift\Runtimes\`）

### Bazel ビルドが失敗する

```cmd
cd mozc\src
bazelisk clean --expunge
```
