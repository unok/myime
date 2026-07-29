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
# x64ビルド（Swift DLL + Mozc MSI）
build-x64.bat

# arm64ビルド（Swift DLL + Mozc MSI）
build-arm64.bat

# クリーンビルド
clean.bat
build-x64.bat

# Mozcのみビルド
build-mozc.bat

# IME再起動
restart-ime.bat
```

### ビルド成果物
- `Mozc_x64.msi` - x64インストーラ
- `build\x64\release\` - x64 DLLファイル群
- ARM64 は現在棚上げ中（docs/upstream-divergence.md 参照。build-arm64.bat は現行の mozc 構造と未整合）

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
├── build-x64.bat           # x64ビルドスクリプト
├── build-arm64.bat         # arm64ビルドスクリプト
├── clean.bat               # クリーンアップ
├── build/x64/release/      # x64ビルド成果物
└── build/arm64/release/    # arm64ビルド成果物
```

## Git構造

### メインリポジトリ
- **リポジトリ**: `git@github.com:unok/myime.git`
- **ブランチ**: `master`

### Submodules

| パス | リポジトリ | ブランチ | 説明 |
|------|-----------|---------|------|
| `mozc/` | `https://github.com/unok/mozc.git` | `patch-myime-next` | Mozc fork (upstream: google/mozc) |
| `src/AzooKeyKanaKanjiConverter/.../azooKey_dictionary_storage` | `https://github.com/azooKey/azooKey_dictionary_storage.git` | - | 辞書データ |
| `src/AzooKeyKanaKanjiConverter/.../azooKey_emoji_dictionary_storage` | `https://github.com/azooKey/azooKey_emoji_dictionary_storage.git` | - | 絵文字辞書データ |

### Subtree

| パス | リポジトリ (fork) | ブランチ | upstream |
|------|------------------|---------|----------|
| `src/AzooKeyKanaKanjiConverter/` | `unok/AzooKeyKanaKanjiConverter` | `windows-llama-patch` | `azooKey/AzooKeyKanaKanjiConverter` |

subtree操作：
```bash
# AzooKeyKanaKanjiConverter を pull
git subtree pull --prefix=src/AzooKeyKanaKanjiConverter https://github.com/unok/AzooKeyKanaKanjiConverter.git windows-llama-patch --squash

# AzooKeyKanaKanjiConverter を push
git subtree push --prefix=src/AzooKeyKanaKanjiConverter https://github.com/unok/AzooKeyKanaKanjiConverter.git windows-llama-patch
```

※ swift-tokenizers は 2026-06 に subtree を廃止（docs/adr/0002 参照）。現在は SwiftPM のリモート依存:
- `unok/swift-tokenizers` の `windows-upstream-patch` ブランチ（upstream `huggingface/swift-transformers` + Windowsパッチ）
- `unok/swift-huggingface` の `windows-patch` ブランチ（FileLockスタブ・fnmatchシム等 約70行）

### Mozc fork について
- **origin**: `https://github.com/unok/mozc.git` (自分のfork)
- **upstream**: `https://github.com/google/mozc.git` (本家)
- AzooKey統合用のカスタマイズを`patch-myime-next`ブランチで管理（2026-06 に upstream へ rebase。旧 `patch-myime` はバックアップとして温存）

## 主要コンポーネント

### Swift Engine (`src/swift-engine/`)
- `azookey-engine.dll` を生成
- AzooKeyKanaKanjiConverterをラップ
- C FFI経由でMozcと連携

### Mozc (`mozc/`)
- `unok/mozc` fork (patch-myime-next branch)
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

### 設定レジストリ（HKCU\Software\Mozc）
設定ダイアログの Conversion engine グループと対応。一覧と意味は docs/architecture.md 参照。
`ZenzaiEnabled`(既定1) / `ZenzaiUseGpu`(0) / `TypoCorrectionEnabled`(1) / `IdleResuggest`(0) / `TypoCorrectionUseAi`(0)。
変更は設定ダイアログから行う（CLI は 2026-07 に廃止。必要なら reg add で直接変更できる）。

### バージョン自動注入
build-x64.bat が `MOZC_VERSION=3.33.<日数>.<UTC時分>` を注入し、ビルドごとに単調増加する。
「インストールしたのに古いまま」はバージョン同一が原因ではなくなった（下記のインストール注意を参照）。

### インストールの注意（実測で確認済みの落とし穴）
- IME の TSF DLL（mozc_tip64.dll）は全 GUI アプリに読み込まれるため、アプリが多いとインストールに5分以上かかる（閉じてからなら15秒程度）
- インストールが「要再起動」で終わることがある（イベントログ MsiInstaller 1038、種類2=使用中ファイルの置換保留）。**再起動するまでディスク上も古い DLL のまま**で、新機能が動かない。「直っていない」と報告された時はまずこれを疑い、`(Get-Item 'C:\Program Files (x86)\Mozc\mozc_tip64.dll').VersionInfo.FileVersion` で実ファイルのバージョンを確認する
- 起動済みアプリはプロセス再起動まで古い DLL を使い続ける。動作検証は必ず新規に開いたアプリで行う

### デバッグ
```batch
# Bazelビルドのみ実行
cd mozc\src
bazelisk build --config=oss_windows //win32/installer:installer_x64
```

タイポ補正・アイドル再サジェストのヘッドレス検証は `session_handler_main` +
`session_handler_tool` の `REQUEST_TYPO_SUGGESTION` コマンドで可能（docs/architecture.md 参照）。
注意: Zenzai 有効環境では session_handler_main が終了時にハングし CPU を消費し続けるため、
実行後は必ず `Stop-Process` すること。

### UACインストーラ検出（解決済みの歴史的メモ）
かつてローカルMSIビルドで、UACの「インストーラ検出」が `build_installer.exe`
（名前に install を含む未署名exe）の起動を error 740 で拒否し
`Permission denied (Exit 126)` で失敗していた。upstream がビルドツールを
`build_msi` に改名して解決済み（google/mozc#1519）。`__COMPAT_LAYER=RunAsInvoker`
の回避策は不要になり削除した。

## 開発タスク: 文節調整機能

※ このセクションは過去の動作検証記録（基準日 2024-12-23）。現在のアーキテクチャ全体は docs/architecture.md を参照。

### 現状 (2024-12-23)

文節調整機能は基本的に動作している。Rewriterがセグメントリサイズを要求し、AzooKeyが各セグメントに対して候補を生成する。

**動作フロー**：
1. ひらがな入力 → インライン候補が表示される
2. スペースを押す → 変換モード（CONVERSION）に入る
3. Rewriterがセグメント分割を要求 → 複数セグメントに分割
4. 各セグメントに対してAzooKeyが候補を生成
5. Shift+左右矢印でセグメント境界を調整可能
6. 左右矢印でセグメント間を移動
7. スペース/下矢印で候補選択

### キーマップ（MS-IME）

変換モード（Conversion）での主要キー：
- `Space` / `Down` → 次の候補（ConvertNext）
- `Left` / `Right` → セグメント移動（SegmentFocusLeft/Right）
- `Shift+Left` / `Shift+Right` → セグメント境界調整（SegmentWidthShrink/Expand）
- `Enter` → 全体確定（Commit）

※ATOKキーマップでは`Down`が`CommitOnlyFirstSegment`にマップされているため動作が異なる

### 関連ファイル

- `mozc/src/converter/azookey_immutable_converter.cc` - AzooKey変換エンジン統合
- `mozc/src/converter/azookey_immutable_converter.h` - ヘッダファイル
- `src/swift-engine/Sources/azookey-engine/AzookeyEngine.swift` - Swift側変換エンジン

### 技術メモ

- `consumed_key_size`: 候補がカバーするひらがな文字数（バイト数ではない）
- `correspondingCount`: Swift側から返される、候補がカバーする文字数（`candidate.rubyCount`）
- セグメント分割: Mozcは複数セグメントを作成して文節ごとに候補を表示する
- ResizeSegment: 文節境界の調整時に呼ばれる関数
