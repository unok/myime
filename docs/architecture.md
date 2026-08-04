# MyIME アーキテクチャ: Mozc ⇔ AzooKey 統合

Mozc（C++ / TSF）をUIフレームワークとし、かな漢字変換を AzooKey（Swift / `azookey-engine.dll`）に委譲するハイブリッド構成の現状を記述する。

調査基準日: 2026-07-29（mozc fork `patch-myime-next`、AzooKey subtree `windows-llama-patch` 時点）

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
| | `SetZenzaiUseGpu(bool)` | 推論バックエンド切替（false=CPU（既定）/ true=Vulkan GPU）。ggml の動的バックエンドロード（`GGML_BACKEND_DL`）で実現し、GPU 指定時のみ ggml-vulkan モジュールをロードする |
| | `GetZenzaiStatus()` | `{enabled, weightPath, inferenceLimit, modelExists, active}` の JSON |
| タイポ補正 | `SetTypoCorrectionEnabled(bool)` / `SetTypoCorrectionBudget(n)` / `SetTypoCorrectionUseAi(bool)` | タイポ補正2パスの有効化・変換予算・AI（Zenzai）による候補評価。Mozc 側は GetProcAddress で任意取得（旧 DLL でも起動可） |
| メモリ | `FreeString(ptr)` | 戻り値文字列の解放 |

**ユーザー学習**: `memory_path`（`%APPDATA%\Mozc\azookey_memory`、`engine_config.h` の `GetAzooKeyMemoryPath()`）が渡されると有効。シークレットモード（`enable_user_history_for_conversion=false`）のリクエストは学習されない。

### ConvertText / GetCandidates の JSON 形式

```json
[{"text": "漢字", "correspondingCount": 3},
 {"text": "学校", "correspondingCount": 3, "typoCorrected": true, "correctedReading": "がっこう"}, ...]
```

- `correspondingCount`: その候補がカバーする**ひらがな文字数**（バイト数ではない）。Swift 側の `candidate.rubyCount` 由来。タイポ補正候補では元キーの文字数（補正読みではなく入力全体を置き換えるため）。
- `typoCorrected` / `correctedReading`: タイポ補正2パスが生成した候補にのみ付く。Mozc 側はこれを見て `SPELLING_CORRECTION` 属性（「もしかして」表示）・`NO_HISTORY_LEARNING`・コストジャンプ（リスト末尾固定）を付与する。

## 変換フロー（セグメント分割を含む）

1. ひらがな入力 → インライン候補表示。スペースで変換モード（CONVERSION）へ。
2. `Converter::Convert()` → `AzooKeyImmutableConverter::Convert()`（`azookey_immutable_converter.cc`）。
3. **セグメントごと**に `ConvertText(segment->key(), allowLearning)` → `ParseCandidatesForSegment()`（単発APIのため呼び出し間に他スレッドの操作が割り込まない）。
4. `ParseCandidatesForSegment` での `correspondingCount` 処理（キー長 N 文字に対して）:
   - `== N`: そのまま採用
   - `< N`: 不足分のひらがなを末尾補完（例: 候補「漢字」+残り「あ」→「漢字あ」）
   - `> N`: スキップ
   - 候補ゼロ: キーそのものをフォールバック候補に
5. `candidate->consumed_key_size = キー文字数` を設定（Mozc が次セグメントの残り計算に使用）。
6. Shift+←/→ で文節境界調整（`ResizeSegment` 経由で再変換）、←/→ でセグメント移動（MS-IMEキーマップ。ATOKでは `Down` が `CommitOnlyFirstSegment` のため挙動が異なる）。

## Mozc 側統合ポイント

| ファイル | 内容 |
|---|---|
| `mozc/src/engine/engine.cc` | `ImmutableConverter` を AzooKey に差し替え。失敗時 NoOp フォールバック |
| `mozc/src/converter/azookey_immutable_converter.cc/.h` | DLLロード・JSONパース・セグメント処理・タイポ候補への属性付与の本体（新規ファイル） |
| `mozc/src/converter/engine_config.h` | エンジン種別（常時 AZOOKEY）・Zenzai モデルパス解決・レジストリ設定の読み取り（新規, ヘッダオンリー） |
| `mozc/src/server/mozc_server_main.cc` | 起動時の Zenzai モデル存在チェック → ダウンロード案内 |
| `mozc/src/gui/zenzai_download/` | `mozc_tool --mode=zenzai_download` ダイアログ（新規） |
| `mozc/src/gui/config_dialog/` | Conversion engine グループのチェックボックス群（レジストリ直読み書き） |
| `mozc/src/protocol/commands.proto` + `session/session.cc` | `REQUEST_TYPO_SUGGESTION` コマンド（アイドル再サジェスト） |
| `mozc/src/prediction/dictionary_predictor.cc` + `rewriter/merger_rewriter.h` | 予測経路でタイポ候補（SPELLING_CORRECTION）がトリムで消えないための保護 |
| `mozc/src/win32/tip/tip_text_service.cc` + `tip_keyevent_handler.cc` | アイドルタイマー（400ms）と UI-only 候補更新 |
| `mozc/src/converter/azookey_user_dictionary.cc/.h` | Mozc ユーザー辞書 → AzooKey 動的ユーザー辞書の一方向反映（新規ファイル、ADR-0003） |
| `mozc/src/rewriter/word_register_rewriter.cc/.h` + `engine/engine_converter.cc` + `session/session.cc` | 予測・変換窓末尾の【辞書登録】候補と、確定せずダイアログ起動する選択処理 |

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

- モデルパスは2箇所を探索（`engine_config.h` で解決）: `%LOCALAPPDATA%\Mozc\models\`（ユーザー領域、ランタイム自動ダウンロードの保存先）→ `%ProgramFiles(x86)%\Mozc\models\`（MSI 配置先）の順
- **有効条件 = モデルファイルの存在 AND レジストリ `ZenzaiEnabled`（既定オン）**: 満たせば `SetZenzaiEnabled(true)` + `SetZenzaiWeightPath` → Swift 側 `ZenzaiMode.on(weight:, inferenceLimit: 10)`。満たさなければ辞書のみの変換。
- 推論バックエンドは既定 CPU。レジストリ `ZenzaiUseGpu`（既定オフ）で Vulkan GPU に切替（`SetZenzaiUseGpu` → ggml の動的バックエンドロード）。llama.cpp は `GGML_BACKEND_DL=ON` でビルドされ、ggml-vulkan.dll は同梱されるがロードは GPU 指定時のみ
- 入手経路は2つ: MSI の `DownloadZenzaiModel` CustomAction（WinINet で Hugging Face から取得、失敗してもインストール続行）、または `mozc_server` 起動時の案内 → `mozc_tool --mode=zenzai_download`
- 状態共有: `HKCU\Software\Mozc` に `ZenzaiActive` / `ZenzaiWeightPath` / `ZenzaiTimestamp` を書き込み、GUI が読む

## タイポ補正（2パス方式）

ローマ字打鍵ミスに対する補正候補を、通常変換とは独立した2パス目で生成する。1パス目（通常変換）は完全無変更で、挙動一致を保証する。

- **生成器**（`TypoCorrectionReadingGenerator.swift`）: 読みから補正読み候補を生成する。パターンはローマ字往復方式（読み→ローマ字逆変換→編集→かな再変換）を基本に、母音補完・ん/っ挿入・隣接キー置換・転置など。カテゴリはラウンドロビンで採用し、往復自己検証（324読み）を通過したテーブルのみ使う
- **2系統の探索**: 読みが valid なかなになったタイポ（がこう→学校）は総当たり生成+スコア選別。アルファベットが残ったタイポ（ありがとうございまs）は残留位置が誤り位置を指すため局所修復し、読み長制限なし
- **選別**（`AzookeyEngine.swift` の `makeTypoCandidates`）: 別 KanaKanjiConverter インスタンス（DicdataStore 共有・学習なし・Zenzai off）で変換し、読み全体カバー・スクリプト変種除外・1文字あたりの絶対バー・1パス目最良候補との1モーラあたり比較で絞る。実測校正値はコード内コメント参照
- **実行タイミング**: スペース変換時（予算12）とアイドル再サジェスト時（予算60）のみ。打鍵毎のサジェストでは走らない。予測器が内部で行うトップ候補用変換（`used_in_predictor_realtime_conversion`）も除外される
- **AI 評価オプション**（レジストリ `TypoCorrectionUseAi`、既定オフ）: 2パス目を Zenzai で評価する。コストが大きい（実測 26ms→154ms）ため変換時のみ適用

## アイドル再サジェスト

入力が止まって 400ms 後に、候補窓だけをタイポ補正込みで更新する。打鍵中の遅延をゼロに保ったまま補正候補を予測窓に出すための仕組み。

1. 打鍵毎に TSF の task window（`tip_text_service.cc`）へ `SetTimer` を再アーム。WM_TIMER は低優先度のため、キューが空いた時（=入力が止まった時）だけ届く
2. 発火時に専用コマンド `SessionCommand::REQUEST_TYPO_SUGGESTION` をサーバへ送る（MOVE_CURSOR 流用ではないため確定取消の undo コンテキストを消さない）
3. セッション層で `idle_resuggest` フラグ付きの再サジェストを実行 → `ConversionOptions` 経由でエンジンまで貫通し、タイポ補正が予算60で走る
4. 応答の preedit が現在の composition と一致する場合のみ `last_output` を差し替えて UI 更新（composition には触らない。打鍵が割り込んでいたら破棄）

予測経路でのタイポ候補は `dictionary_predictor.cc`（`RemoveMissSpelledCandidates` の除外ガード + トリム後の再追加）と `merger_rewriter.h`（サジェスト件数トリムからの `SPELLING_CORRECTION` 保護）を通って表示に到達する。ヘッドレス検証は `session_handler_tool` の `REQUEST_TYPO_SUGGESTION` コマンドで可能。

## ユーザー辞書と単語登録

Mozc ユーザー辞書（user_dictionary.db）を正本とし、AzooKey へは一方向反映する（[ADR-0003](./adr/0003-mozc-user-dictionary-as-source-of-truth.md)）。用語は CONTEXT.md「ユーザー辞書と単語登録」節を参照。

**反映経路（Phase 1）**: エンジン初期化時と Reload 時（単語登録ダイアログの保存が `client_->Reload()` を呼ぶ）に、`converter/azookey_user_dictionary.cc` が db を直接ロードして JSON 化し、DLL の `SetUserDictionary` へ全量置換でプッシュ → Swift 側で `importDynamicUserDictionary`（メモリ上・非永続）。品詞は C++ 側で十数種のカテゴリ文字列に落とし、Swift 側で CID/MID/コストへ変換。未知品詞は普通名詞。抑制単語と NO_POS は対象外。`SetUserDictionary` を持たない旧 DLL では null チェックでスキップ。

**辞書登録候補（Phase 2）**: `rewriter/word_register_rewriter.cc` が予測窓・変換窓の各セグメント末尾に【辞書登録】（`COMMAND_CANDIDATE` + 新 Command `LAUNCH_WORD_REGISTER_DIALOG`）を注入。モバイル（mixed_conversion）・predictor 内部変換（`used_in_predictor_realtime_conversion`）・空キー・候補ゼロには注入しない。選択時は全経路（SELECT/SUBMIT/数字キー/サジェスト commit）で `MaybeLaunchWordRegisterCandidate()` が確定を抑止して composition を取り消し、`Output.launch_tool_mode=WORD_REGISTER_DIALOG` と読み（`launch_tool_arg`、予測窓=入力全体、変換窓=フォーカス文節）を返す。TSF（`tip_edit_session_impl.cc` → `HandleToolOutput`）が読みを環境変数に設定して `mozc_tool --mode=word_register_dialog` を起動（ダイアログ側は無改修で macOS と同じ環境変数を読む）。Ctrl+F7（入力前状態）でも起動可。

**ヘッドレス検証の注意**: `session_handler_main.exe` は DLL プリロード対策により azookey-engine.dll を「自分と同じディレクトリ」からのみロードするため、exe を `build/x64/release/` にコピーして実行する。`--profile` は Windows では未存在ディレクトリしか指定できない（既存だと CreateDirectoryW が失敗）。サジェスト末尾の固定表示は `merger_rewriter.h` のトリム保護（タイポ補正と同じ関門、辞書登録はさらに後）を通る。

## パススルー英数切替キー

レジストリ `PassthroughHalfAlnumKeys`（REG_SZ、例 `Ctrl+T Ctrl+Q`）に設定したキーを、アプリへそのまま通しつつ半角英数モードへ切り替える。プレフィックスキー（tmux 等）の後続入力が IME に食われないようにする機能。

実装は TSF の2段階（`win32/tip/tip_keyevent_handler.cc`）を使い分ける。**OnTestKeyDown では副作用を起こさず eaten=TRUE を返すだけ**にし、**OnKeyDown で `TipEditSession::SwitchInputModeAsync` を呼んでから eaten=FALSE を返す**。TSF は OnTestKeyDown が FALSE を返すと OnKeyDown を呼ばず、テスト段階では edit session も与えないため、切替を OnTestKeyDown 側で要求すると「キーはアプリに届くがモードだけ切り替わらない」状態になる（実機で発生した不具合）。

- 設定した全キーが同じ動作で、常に HALF_ASCII への片方向切替（トグルや「ひらがなへ戻すキー」は存在しない。既に HALF_ASCII のときは切替コマンドを送らずパススルーのみ）
- 発動条件: keydown・IME オン・無効コンテキスト（パスワード欄等）でない・未確定文字列なし・修飾キー込みの完全一致
- 書式はスペース区切りで、Ctrl/Alt/Shift を `+` で連結しキー本体は英数字1文字。修飾キーなしのトークンは無効（素の文字を設定するとその文字の日本語入力が不可能になるため）
- パースとマッチは `win32/tip/tip_passthrough_key.cc`（単体テスト `//win32/tip:tip_passthrough_key_test`）。設定値はキーイベントごとに生文字列を読み、変化したときだけ再パースする（IME 再起動不要）
- 設定 UI は設定ダイアログ Conversion engine グループの「Passthrough alnum switch keys」欄（REG_SZ を読み書き）

## レジストリ設定一覧（HKCU\Software\Mozc）

設定ダイアログ（Conversion engine グループ）と対応する。config.proto は変更せず、レジストリ直読み方式。

| 値 | 型 | 既定 | 意味 |
|---|---|---|---|
| `ZenzaiEnabled` | DWORD | 1 | Zenzai（LLM変換）を使う（モデル存在時のみ有効） |
| `ZenzaiUseGpu` | DWORD | 0 | Zenzai 推論を Vulkan GPU で行う |
| `TypoCorrectionEnabled` | DWORD | 1 | タイポ補正候補を出す |
| `IdleResuggest` | DWORD | 0 | アイドル時にタイポ補正込みで候補窓を更新する |
| `TypoCorrectionUseAi` | DWORD | 0 | タイポ候補の評価に Zenzai を使う（変換時のみ・低速） |
| `PassthroughHalfAlnumKeys` | REG_SZ | （空） | アプリへ渡しつつ半角英数へ切り替えるキーのリスト |

エンジンが書き込む状態通知（GUI が読む）: `ZenzaiActive` / `ZenzaiGpuActive` / `ZenzaiWeightPath` / `ZenzaiTimestamp`。

## バージョン自動注入

`build-x64.bat` が `MOZC_VERSION=3.33.<2009-05-24からの日数>.<UTC時刻HHmm>` を `--action_env` で注入する（mozc の `--use_mozc_version_env` フック）。ビルドごとにバージョンが単調増加するため、同版上書きによる「インストールしたのにバイナリが古いまま」が起きない。Windows Installer のファイル置換規則がバージョン比較で決まることへの対策。
