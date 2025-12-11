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

- Windows 10/11 (x64 または ARM64)
- Visual Studio 2022 (C++ ワークロード)
- Swift 6.2.1 以上 (Windows版)
- Bazelisk
- Python 3.x
- Windows SDK 10.0.22621.0+
- Vulkan 対応 GPU (Zenzai AI 使用時、オプション)

### 2. ビルド

```cmd
# リポジトリをクローン（サブモジュール含む）
git clone --recursive https://github.com/unok/myime.git
cd myime

# x64 ビルド
build-x64.bat

# ARM64 ビルド
build-arm64.bat
```

### 3. インストール

```cmd
# 管理者権限で MSI を実行
Mozc_x64.msi    # x64 の場合
Mozc_arm64.msi  # ARM64 の場合
```

インストール時に Zenzai AI モデルが自動でダウンロードされます（約500MB）。

### 4. アンインストール

Windows の「設定」→「アプリ」→「Mozc」からアンインストール

## ビルドスクリプト

| スクリプト | 説明 |
|-----------|------|
| `build-x64.bat` | x64 用 Swift DLL + Mozc MSI をビルド |
| `build-arm64.bat` | ARM64 用 Swift DLL + Mozc MSI をビルド |
| `build-mozc.bat` | Mozc のみビルド（Swift DLL はスキップ） |
| `clean.bat` | ビルド成果物をクリーンアップ |
| `restart-ime.bat` | IME プロセスを再起動 |

## ビルド成果物

```
myime/
├── Mozc_x64.msi              # x64 インストーラ
├── Mozc_arm64.msi            # ARM64 インストーラ
└── build/
    ├── x64/release/          # x64 DLL
    │   └── azookey-engine.dll
    └── arm64/release/        # ARM64 DLL
        └── azookey-engine.dll
```

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
- インストール場所: `%ProgramFiles%\Mozc\models\`
- インストール時に HuggingFace から自動ダウンロード
- ダウンロードに失敗してもインストールは継続（オフライン環境対応）

### 手動でモデルをダウンロードする場合

```cmd
# モデルディレクトリを作成
mkdir "%ProgramFiles%\Mozc\models"

# モデルをダウンロード
curl -L -o "%ProgramFiles%\Mozc\models\ggml-model-Q5_K_M.gguf" ^
  "https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf"
```

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

- モデルファイルが `%ProgramFiles%\Mozc\models\ggml-model-Q5_K_M.gguf` に存在するか確認
- Vulkan 対応 GPU が必要（CPU フォールバックはなし）

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
git pull origin patch-myime
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
