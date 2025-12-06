# MyIme

Windows用日本語入力メソッド (IME)。AzooKeyKanaKanjiConverter + Zenzai (Vulkan) を使用。

## アーキテクチャ

```
[C# IME (Windows TSF)]
        ↓ P/Invoke (C ABI)
[Swift DLL (azookey-engine.dll)]
        ↓
[AzooKeyKanaKanjiConverter + Zenzai]
        ↓
[Vulkan (GPU LLM推論)]
```

## クイックスタート

### 1. 必要条件

- Windows 10/11 (x64 または ARM64)
- Visual Studio 2022 (C++ ワークロード)
- Swift 6.2.1 以上 (Windows版)
- .NET 8.0 SDK
- Git
- Vulkan 対応 GPU (Zenzai 使用時、オプション)

### 2. セットアップ

```cmd
# リポジトリをクローン
git clone https://github.com/yourusername/myime.git
cd myime

# 辞書データをセットアップ
setup-dictionaries.bat

# 全体をビルド
build-all.bat
```

### 3. テスト実行

```cmd
# テストプログラムを実行
test-ime.bat
```

### 4. IME のインストール

```cmd
# 管理者権限で実行
scripts\register-ime.ps1
```

## ビルドスクリプト

| スクリプト | 説明 |
|-----------|------|
| `build-swift-final.bat` | Swift エンジンをビルド (VS環境自動設定) |
| `build-all.bat` | Swift と C# を両方ビルド |
| `test-ime.bat` | テストプログラムの作成と実行 |
| `setup-dictionaries.bat` | 辞書データのセットアップ |

## 設定

`config.json` で以下を設定可能:

```json
{
  "dictionaryPath": "dictionaries\\azooKey_dictionary_storage",
  "memoryPath": "userdata\\memory",
  "zenzaiEnabled": false,
  "zenzaiInferenceLimit": 10,
  "zenzaiWeightPath": ""
}
```

### Zenzai (AI変換) を有効にする

1. LLM モデルをダウンロード
2. `config.json` の `zenzaiWeightPath` にモデルパスを設定
3. `zenzaiEnabled` を `true` に設定

## ディレクトリ構造

```
myime/
├── build-swift-final.bat    # Swift ビルド
├── build-all.bat            # 全体ビルド  
├── test-ime.bat             # テスト実行
├── setup-dictionaries.bat   # 辞書セットアップ
├── config.json              # 設定ファイル
├── src/
│   ├── swift-engine/        # Swift DLL (変換エンジン)
│   │   ├── Package.swift
│   │   └── Sources/
│   └── csharp-ime/          # C# IME
│       ├── MyIme.sln
│       ├── MyIme.Core/      # P/Invoke ラッパー
│       └── MyIme.Tsf/       # TSF 実装
├── scripts/                 # 追加スクリプト
├── dictionaries/            # 辞書データ (サブモジュール)
├── build/                   # ビルド出力
└── test/                    # テストプログラム
```

## トラブルシューティング

### Swift ビルドが失敗する

- Visual Studio 2022 の C++ ワークロードがインストールされているか確認
- Swift 6.2.1 以上がインストールされているか確認 (`swift --version`)

### 辞書が見つからない

```cmd
# サブモジュールを更新
git submodule update --init --recursive
```

### DLL が読み込めない

- Visual C++ 再頒布可能パッケージをインストール
- `build\x64\release\azookey-engine.dll` が存在するか確認

## 開発

### デバッグビルド

```cmd
# build-swift-final.bat を編集
# "release" を "debug" に変更
```

### ARM64 対応

スクリプト内の `x64` を `arm64` に変更してビルド。

## ライセンス

MIT License

## 参考

- [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter)
- [azooKey-Windows](https://github.com/fkunn1326/azooKey-Windows)
- [llama.cpp](https://github.com/ggerganov/llama.cpp)