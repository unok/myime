# MyIME

Windows向け日本語IME。MozcのUIフレームワークとAzooKeyのかな漢字変換エンジン（Zenzai AI対応）を組み合わせたハイブリッドIME。

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│                   Mozc (UI)                      │
│  - TSF/IME フレームワーク                        │
│  - 候補ウィンドウ                                │
│  - 設定ツール                                    │
└─────────────────┬───────────────────────────────┘
                  │ C FFI
┌─────────────────▼───────────────────────────────┐
│           azookey-engine.dll (Swift)            │
│  - KanaKanjiConverterModule                     │
│  - Zenzai AI (llama.cpp)                        │
└─────────────────────────────────────────────────┘
```

## クイックスタート

### 1. 必要条件

- Windows 10/11 (x64)　※ ARM64 対応は現在棚上げ中
- Visual Studio 2022 (C++ ワークロード)
- Swift 6.2.1 以上 (Windows版)
- Bazelisk
- Python 3.x
- Windows SDK 10.0.22621.0+

Zenzai AI は既定で CPU 推論のため GPU は不要です。設定で GPU（Vulkan）推論に切り替える場合のみ Vulkan 対応 GPU が必要です。

### 2. ビルド

```cmd
# リポジトリをクローン（サブモジュール含む）
git clone --recursive https://github.com/unok/myime.git
cd myime

# x64 ビルド
build-x64.bat

# ARM64 ビルド（現在棚上げ中・動作しません）
# build-arm64.bat
```

### 3. インストール

```cmd
# 管理者権限で MSI を実行
Mozc_x64.msi
```

インストール時に Zenzai AI モデルが自動でダウンロードされます（約500MB）。

### 4. アンインストール

Windows の「設定」→「アプリ」→「Mozc」からアンインストール

## ビルドスクリプト

| スクリプト | 説明 |
|-----------|------|
| `build-x64.bat` | x64 用 Swift DLL + Mozc MSI をビルド |
| `build-arm64.bat` | ARM64 用ビルド（**現在棚上げ中・動作しません**） |
| `build-mozc.bat` | Mozc のみビルド（Swift DLL はスキップ） |
| `clean.bat` | ビルド成果物をクリーンアップ |
| `restart-ime.bat` | IME プロセスを再起動 |

## ビルド成果物

```
myime/
├── Mozc_x64.msi              # x64 インストーラ
└── build/
    └── x64/release/          # x64 DLL
        └── azookey-engine.dll
```

ビルドごとにバージョンが自動で上がる（`3.33.<日数>.<時分>`）ため、同じ MSI 名でも常に上書きインストールできます。

## ディレクトリ構造

```
myime/
├── mozc/                    # Mozc submodule (unok/mozc fork)
│   └── src/
│       ├── win32/          # Windows TSF 実装
│       └── MODULE.bazel    # Bazel 設定
├── src/
│   ├── swift-engine/       # Swift 変換エンジン
│   │   ├── Package.swift
│   │   └── Sources/
│   └── AzooKeyKanaKanjiConverter/  # かな漢字変換 (subtree)
├── build-x64.bat           # x64 ビルド
├── build-arm64.bat         # ARM64 ビルド
└── build/                  # ビルド成果物
```

## Zenzai AI について

Zenzai は LLM を使った高精度なかな漢字変換エンジンです。

- モデル: `zenz-v3.1-small` (約500MB)
- モデルの場所: `%LOCALAPPDATA%\Mozc\models\`（ユーザー領域）または `%ProgramFiles(x86)%\Mozc\models\`（MSI 配置先）
- インストール時に HuggingFace から自動ダウンロード
- ダウンロードに失敗してもインストールは継続（オフライン環境対応）
- 推論は既定で CPU。設定で Vulkan GPU に切替可能

### 手動でモデルをダウンロードする場合

```cmd
# モデルディレクトリを作成
mkdir "%LOCALAPPDATA%\Mozc\models"

# モデルをダウンロード
curl -L -o "%LOCALAPPDATA%\Mozc\models\ggml-model-Q5_K_M.gguf" ^
  "https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf"
```

## 設定

Mozc プロパティ（設定ダイアログ）の Conversion engine グループで切り替えます。実体は `HKCU\Software\Mozc` のレジストリ値です（一覧は [docs/architecture.md](docs/architecture.md) 参照）。

| 設定 | 既定 | 内容 |
|---|---|---|
| Zenzai | オン | LLM による変換（モデルがある場合のみ） |
| GPU (Vulkan) | オフ | Zenzai の推論を GPU で行う |
| タイポ補正 | オン | 打鍵ミスの補正候補を変換時とアイドル時に表示（例: `gakou`→学校） |
| アイドル再サジェスト | オフ | 入力が止まって0.5秒後に予測窓へ補正候補を追加 |
| タイポ補正の AI 評価 | オフ | 補正候補の評価に Zenzai を使う（変換時のみ・低速） |

## トラブルシューティング

### Swift ビルドが失敗する

- Visual Studio 2022 の C++ ワークロードがインストールされているか確認
- Swift 6.2.1 以上がインストールされているか確認 (`swift --version`)
- Swift Runtime が正しい場所にあるか確認 (`%LOCALAPPDATA%\Programs\Swift\Runtimes\`)

### Bazel ビルドが失敗する

```cmd
# Bazel キャッシュをクリア
cd mozc\src
bazelisk clean --expunge
```

### IME が表示されない

1. コンピュータを再起動
2. 「設定」→「時刻と言語」→「言語と地域」→「日本語」→「言語オプション」で Mozc を追加

### Zenzai が動作しない

- モデルファイルが `%LOCALAPPDATA%\Mozc\models\` か `%ProgramFiles(x86)%\Mozc\models\` に存在するか確認
- 設定ダイアログで Zenzai が有効になっているか確認（既定は有効）
- GPU 設定を有効にしている場合は Vulkan 対応 GPU とドライバが必要。動かない場合は GPU 設定を外せば CPU で動作します

### インストールが遅い・変更が反映されない

- IME の DLL は起動中の全アプリに読み込まれるため、アプリを多く開いているとインストールに数分かかることがあります（アプリを閉じてから実行すると速い）
- インストールが「再起動が必要」で終わった場合（イベントログ MsiInstaller 1038）、**再起動するまで古い DLL が動き続けます**。新機能が反映されない時はまずこれを疑い、再起動してください
- 起動済みのアプリは再起動するまで古い DLL を使い続けます。動作確認は新しく開いたアプリで行ってください

## 開発

### デバッグビルド

```cmd
# mozc/src で直接 Bazel を実行
cd mozc\src
bazelisk build --config=oss_windows //win32/installer:installer_x64
```

### Mozc submodule の更新

```cmd
cd mozc
git pull origin patch-myime-next
cd ..
git add mozc
git commit -m "Update mozc submodule"
```

## ライセンス

- MyIME: MIT License
- Mozc: BSD 3-Clause License
- AzooKeyKanaKanjiConverter: MIT License
- llama.cpp: MIT License

## 参考

- [Mozc](https://github.com/google/mozc) - Google 日本語入力のオープンソース版
- [AzooKeyKanaKanjiConverter](https://github.com/ensan-hcl/AzooKeyKanaKanjiConverter) - かな漢字変換エンジン
- [azooKey-Windows](https://github.com/fkunn1326/azooKey-Windows) - Windows 移植の参考
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - LLM 推論エンジン
