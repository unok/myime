# MyIME - Claude Code Project Guide

## プロジェクト概要

Windows向け日本語IME。MozcのUIフレームワークとAzooKeyのかな漢字変換エンジン（Zenzai AI対応）を組み合わせたハイブリッドIME。

## ビルド

### 必要環境
- Windows 10/11 (x64)
- Swift 6.2.1+
- Visual Studio 2022 (C++ workload)
- Bazelisk
- Python 3.x
- Windows SDK 10.0.22621.0+

### ビルドコマンド
```batch
# フルビルド（Swift DLL + Mozc MSI）
build.bat

# クリーンビルド
clean.bat
build.bat

# Mozcのみビルド
build-mozc.bat

# IME再起動
restart-ime.bat
```

### ビルド成果物
- `Mozc64.msi` - インストーラ
- `build\x64\release\` - DLLファイル群

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

## ディレクトリ構成

```
myime/
├── mozc/                    # Mozc submodule (unok/mozc fork)
│   └── src/
│       ├── win32/          # Windows TSF実装
│       └── MODULE.bazel    # Bazel設定
├── src/
│   ├── swift-engine/       # Swift変換エンジン
│   │   ├── Package.swift
│   │   └── Sources/
│   ├── AzooKeyKanaKanjiConverter/  # かな漢字変換 (subtree)
│   └── csharp-ime/         # C# IME実装（実験的）
├── build.bat               # メインビルドスクリプト
├── clean.bat               # クリーンアップ
└── build/x64/release/      # ビルド成果物
```

## 主要コンポーネント

### Swift Engine (`src/swift-engine/`)
- `azookey-engine.dll` を生成
- AzooKeyKanaKanjiConverterをラップ
- C FFI経由でMozcと連携

### Mozc (`mozc/`)
- `unok/mozc` fork (patch-myime branch)
- AzooKey DLLを組み込むカスタマイズ済み
- Bazelでビルド

### llama.cpp DLLs
- `src/AzooKeyKanaKanjiConverter/lib/windows/` に配置
- Zenzai AI機能に必要
- `ggml.dll`, `llama.dll` など

## 開発メモ

### Swift Runtime DLLの場所
```
%LocalAppData%\Programs\Swift\Runtimes\{version}\usr\bin\
```
※ `Toolchains` ではなく `Runtimes` ディレクトリ

### Bazel設定
- `mozc/src/MODULE.bazel` - 外部依存定義
- `mozc/src/bazel/BUILD.azookey_dlls.bazel` - AzooKey DLL定義
- `@azookey_dlls` リポジトリは `../../build/x64/release` を参照

### デバッグ
```batch
# Bazelビルドのみ実行
cd mozc\src
bazelisk build --config=oss_windows //win32/installer:installer
```
