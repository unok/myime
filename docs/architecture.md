# MyIME アーキテクチャ: Mozc ⇔ AzooKey 統合

Mozc（C++ / TSF）をUIフレームワークとし、かな漢字変換を AzooKey（Swift / `azookey-engine.dll`）に委譲するハイブリッド構成の現状を記述する。

調査基準日: 2026-06-11（mozc fork `patch-myime`、AzooKey subtree `windows-llama-patch` 時点）

## 全体構成

```
┌─────────────────────────────────────────────────┐
│                   Mozc (UI)                      │
│  TSF/IMEフレームワーク・候補ウィンドウ・設定ツール  │
│                                                  │
│  engine/engine.cc ── ImmutableConverter差し替え   │
│       │                                          │
│  converter/azookey_immutable_converter.cc        │
│       │  LoadLibraryW("azookey-engine.dll")      │
└───────┼──────────────────────────────────────────┘
        │ C FFI（JSON文字列で候補受け渡し）
┌───────▼──────────────────────────────────────────┐
│        azookey-engine.dll (Swift)                │
│  src/swift-engine/Sources/azookey-engine/        │
│       │                                          │
│  AzooKeyKanaKanjiConverter (subtree)             │
│       │ ZenzaiMode .on/.off                      │
│  llama.cpp (ggml*.dll, llama.dll) ← Zenzai AI    │
└──────────────────────────────────────────────────┘
```

- **動的ロード**: Mozc は DLL に静的リンクせず、実行時に `LoadLibraryW` + `GetProcAddress` で取得する（`azookey_immutable_converter.cc` の `AzooKeyDllLoader`）。DLL ロード失敗時は `NoOpImmutableConverter` にフォールバックするため、Mozc 単体でもビルド・起動可能。
- **初期化失敗時**: `NoOpImmutableConverter` にフォールバックし、変換機能のみ無効化される（IME自体は落ちない）。

## C FFI 関数一覧

`src/swift-engine/Sources/azookey-engine/AzookeyEngine.swift` でエクスポート。文字列の戻り値は malloc 済みで、呼び出し側が `FreeString` で解放する。

全エクスポート関数は DLL 内部のロックで排他される（Mozc 側から複数スレッドで呼ばれても安全）。

| 分類 | 関数 | 役割 |
|---|---|---|
| 初期化 | `Initialize(dictionaryPath, memoryPath) -> Int32` | KanaKanjiConverter 生成。成功=1/失敗=0。参照カウント方式（ReloadModules で新旧インスタンスが交差しても安全） |
| | `Shutdown()` | 参照カウントを減らし、0 になったら状態クリア |
| | `LoadConfig(configPath)` | JSON設定読み込み（辞書・メモリ・Zenzai） |
| **変換（主経路）** | `ConvertText(key, allowLearning) -> JSON` | **単発変換API**。key（UTF-8ひらがな）の候補リストを1呼び出しで返す。Mozc の `Convert()` はこれのみ使用。`allowLearning=0` でシークレットモード時の学習を抑止 |
| テキスト操作（補助） | `AppendText(utf8)` | ひらがなをカーソル位置に追加（`inputStyle: .direct`） |
| | `RemoveText(count)` / `ShrinkText()` | 文字削除 |
| | `MoveCursor(offset)` | カーソル移動 |
| | `ClearText()` | 構成テキストと候補をリセット |
| 変換（補助） | `GetComposedText()` | 最優候補の文字列 |
| | `GetCandidates()` | 現在の構成テキストの候補リストを JSON で返す |
| | `SelectCandidate(index)` | 候補確定（学習有効時は履歴に反映） |
| Zenzai制御 | `SetZenzaiEnabled(bool)` / `SetZenzaiInferenceLimit(n)` / `SetZenzaiWeightPath(path)` | Zenzai 設定 |
| | `GetZenzaiStatus()` | `{enabled, weightPath, inferenceLimit, modelExists, active}` の JSON |
| メモリ | `FreeString(ptr)` | 戻り値文字列の解放 |

**ユーザー学習**: `memory_path`（`%APPDATA%\Mozc\azookey_memory`、`engine_config.h` の `GetAzooKeyMemoryPath()`）が渡されると有効。シークレットモード（`enable_user_history_for_conversion=false`）のリクエストは学習されない。

### ConvertText / GetCandidates の JSON 形式

```json
[{"text": "漢字", "correspondingCount": 3}, ...]
```

- `correspondingCount`: その候補がカバーする**ひらがな文字数**（バイト数ではない）。Swift 側の `candidate.rubyCount` 由来。

## 変換フロー（セグメント分割を含む）

1. ひらがな入力 → インライン候補表示。スペースで変換モード（CONVERSION）へ。
2. `Converter::Convert()` → `AzooKeyImmutableConverter::Convert()`（`azookey_immutable_converter.cc:577`）。
3. **セグメントごと**に `ConvertText(segment->key(), allowLearning)` → `ParseCandidatesForSegment()`（単発APIのため呼び出し間に他スレッドの操作が割り込まない）。
4. `ParseCandidatesForSegment` での `correspondingCount` 処理（キー長 N 文字に対して）:
   - `== N`: そのまま採用
   - `< N`: 不足分のひらがなを末尾補完（例: 候補「漢字」+残り「あ」→「漢字あ」）
   - `> N`: スキップ
   - 候補ゼロ: キーそのものをフォールバック候補に
5. `candidate->consumed_key_size = キー文字数` を設定（Mozc が次セグメントの残り計算に使用）。
6. Shift+←/→ で文節境界調整（`ResizeSegment` → `ParseCandidatesForResizedSegment`）、←/→ でセグメント移動（MS-IMEキーマップ。ATOKでは `Down` が `CommitOnlyFirstSegment` のため挙動が異なる）。

## Mozc 側統合ポイント

| ファイル | 内容 |
|---|---|
| `mozc/src/engine/engine.cc:108-135` | `ImmutableConverter` を AzooKey に差し替え。失敗時 NoOp フォールバック |
| `mozc/src/converter/azookey_immutable_converter.cc/.h` | DLLロード・JSONパース・セグメント処理の本体（新規ファイル, 867行） |
| `mozc/src/converter/engine_config.h` | エンジン種別（常時 AZOOKEY）と Zenzai モデルパス解決（新規, ヘッダオンリー） |
| `mozc/src/server/mozc_server_main.cc` | 起動時の Zenzai モデル存在チェック → ダウンロード案内 |
| `mozc/src/gui/zenzai_download/` | `mozc_tool --mode=zenzai_download` ダイアログ（新規） |

## ビルド・パッケージング配線

`build-x64.bat` の4ステップ:

1. **依存チェック**: Swift 6.2.1+ / VS2022 / Bazelisk / Windows SDK / llama.cpp ライブラリ（`src/AzooKeyKanaKanjiConverter/lib/windows/`、なければ `scripts/ci/build-llama-cpp.bat` でソースビルド）
2. **Swift DLL ビルド**: `swift build -c release` → `azookey-engine.dll` + Swift Runtime DLL群 + リソースバンドル（辞書データ）を `build/x64/release/` へコピー
3. **llama.cpp DLL コピー**: `ggml*.dll`, `llama.dll` 等を同上へ
4. **Mozc ビルド**: `bazelisk build --config=oss_windows //win32/installer:installer_x64` → `bazel-bin/win32/installer/Mozc_x64.msi`

Bazel との接続:

- `mozc/src/MODULE.bazel` の `new_local_repository(@azookey_dlls, path="../../build/x64/release")` がステップ2-3の出力を参照
- `bazel/BUILD.azookey_dlls.bazel` が DLL群の filegroup を定義
- `win32/installer/BUILD.bazel` が `build_installer.py --azookey_dll_dir=...` 経由で WiX（`installer_oss_64bit.wxs`）に渡し、全 DLL を `Program Files\Mozc\` に同梱

CI（`.github/workflows/build-x64.yml`）は llama.cpp をソースからビルドしてキャッシュする（ビルド済み DLL の git 管理は不要 — [upstream-divergence.md](./upstream-divergence.md) 参照）。

## Zenzai 有効化の仕組み

- モデルパス: `%ProgramFiles%\Mozc\models\ggml-model-Q5_K_M.gguf`（`engine_config.h` で解決）
- **モデルファイルの存在だけで自動 on/off**: 存在すれば `SetZenzaiEnabled(true)` + `SetZenzaiWeightPath` → Swift 側 `ZenzaiMode.on(weight:, inferenceLimit: 10)`。なければ辞書のみの変換。
- 入手経路は2つ: MSI の `DownloadZenzaiModel` CustomAction（WinINet で Hugging Face から取得、失敗してもインストール続行）、または `mozc_server` 起動時の案内 → `mozc_tool --mode=zenzai_download`
- 状態共有: `HKCU\Software\Mozc` に `ZenzaiActive` / `ZenzaiWeightPath` / `ZenzaiTimestamp` を書き込み、GUI が読む
