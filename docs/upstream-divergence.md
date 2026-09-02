# upstream divergence 棚卸し

fork / subtree が upstream に対して持つパッチの一覧と、各パッチの要否・処分を記録する。運用は**最小パッチ方針**（[CONTEXT.md](../CONTEXT.md) 参照: upstream 既存ファイルへの差分を最小化、新規ファイル追加は許容）に従う。

調査基準日: **2026-09-02**。upstream は動き続けるため、rebase / subtree pull のたびに本ドキュメントを更新すること。進行中の追従作業は Issue #56 にまとめている。

## サマリ

| リポジトリ | fork 独自パッチ | upstream からの遅れ | 方針 |
|---|---|---|---|
| mozc（`unok/mozc` `patch-myime-next`） | 43 コミット（+4,708/−27、67 ファイル） | **0**（2026-09-02 に `4b1953a93`（2026-08-27）へ rebase 済み） | 定期追従。次回の衝突箇所は §1 |
| AzooKeyKanaKanjiConverter（`unok/AzooKeyKanaKanjiConverter` `windows-llama-patch`） | 10 コミット（Swift 4 ファイルを含む） | 69 コミット（分岐点 2025-08-26、約 12 か月） | #49 で追従。upstream main の上に Windows パッチを移植し直す |
| swift-tokenizers（`unok/swift-tokenizers` `windows-upstream-patch`） | 2 コミット | 6 コミット（基点 2026-05-19） | #50 で rebase |
| swift-huggingface（`unok/swift-huggingface` `windows-patch`） | 1 コミット | 2 コミット（基点 v0.9.0） | #50 で rebase。upstream への Windows 対応 PR は未着手 |

## 1. mozc fork（`patch-myime-next`）

### rebase 履歴

| 日付 | upstream の位置 | 結果 |
|---|---|---|
| 2026-06-12 | `fea1ebace`（2026-06-11） | 旧 `patch-myime` から `patch-myime-next` へ。独自コミット 14 → 12（陳腐化パッチ・ノイズ・ARM64 関連を破棄、`ConversionOptions` API 移行、universal installer 構造へ移行） |
| 2026-09-02 | `4b1953a93`（2026-08-27、109 コミット分） | 41 コミットをそのまま rebase し、proto 番号の振り直しと DLL リスト整理を追加して 43 コミット。旧先端はブランチ `patch-myime-next-backup-20260902` に温存 |

2026-09-02 の rebase で解決した衝突は 4 件。

- `prediction/realtime_decoder.cc`（2 件）: upstream が `MakeSegments` / `ConversionSegmentsToResult` を `converter/converter_util.cc` へ移動。fork 側の変更（`description` 引き継ぎ）は後続コミットで撤回済みだったため upstream 側を採用
- `converter/BUILD.bazel` と `converter/converter.cc`: upstream の `converter_util` 追加と fork の `engine_config` 追加が隣接。両方を残す
- `session/session.cc`: upstream が `SuggestWithPreferences` を `Suggest(composer, context, preferences)` に改名。fork のアイドル再サジェスト分岐を新名で書き直す。他の呼び出し箇所は自動的に新名で適用された

検証: `//win32/tip:tip_text_service_impl` のビルドと PR Tests の 8 テストがローカルで通過（Bazel 9.0.2）。upstream の MODULE.bazel 追加分（abseil-py 2.1.0、google_benchmark 1.9.5、re2）はそのまま取り込み。ツールチェーン（Qt 6.9.1、LLVM 20.1.1、Ninja 1.13.2）は変更なし。

### proto 番号

fork が追加した `SessionCommand::REQUEST_TYPO_SUGGESTION` と `Output.launch_tool_arg` は、2026-09-02 に **1000** へ移した。それまでの 28 / 27 は upstream の次の追加番号（`REQUEST_NWP = 27`、`server_version = 26` の直後）と正面衝突する位置だった。以後 fork で proto フィールドを足すときは 1000 番台を使う。クライアント（TIP）とサーバは同じ MSI で更新されるため互換性の問題はない。

### 独自差分の所在（次回 rebase の衝突ホットスポット）

いずれも myime 固有機能のため upstream PR 候補ではない。

| 領域 | ファイル | 内容 |
|---|---|---|
| converter | `azookey_immutable_converter.cc/.h`（新規）、`azookey_user_dictionary.cc/.h`（新規） | AzooKey DLL のロードと JSON 候補の取り込み、タイポ候補の属性付与、Mozc ユーザー辞書の AzooKey へのプッシュ |
| converter | `engine_config.h` | レジストリ読み取り（ZenzaiEnabled / ZenzaiUseGpu / TypoCorrectionEnabled / IdleResuggest / TypoCorrectionUseAi / パススルーキー）とモデルパス探索 |
| converter | `converter.cc` | AzooKey 時の `CompletePosIds` 早期 return、`Reload` でのユーザー辞書プッシュ |
| engine | `engine.cc`、`engine_converter.cc`、`engine_converter_interface.h` | `NoOpImmutableConverter`、`ConversionPreferences.idle_resuggest`、辞書登録候補の確定抑止 |
| protocol | `commands.proto` | `REQUEST_TYPO_SUGGESTION = 1000`、`Output.launch_tool_arg = 1000` |
| session | `session.cc/.h`、`session_handler_tool.cc/.h` | `REQUEST_TYPO_SUGGESTION` ハンドラ、ヘッドレス検証コマンド |
| request | `options.h` | `ConversionOptions.idle_resuggest` |
| prediction | `dictionary_predictor.cc`、`result.cc` | SPELLING_CORRECTION と辞書登録候補のトリム後再追加、AZ / AZ1 デバッグラベル |
| rewriter | `merger_rewriter.h`、`word_register_rewriter.cc/.h`（新規） | サジェスト件数トリムからの保護、辞書登録候補の注入 |
| gui | `config_dialog/*`、`zenzai_download/*`（新規）、`about_dialog/*` | Conversion engine グループとパススルーキー表、Zenzai モデル DL、バージョン表示 |
| win32/tip | `tip_text_service.cc`、`tip_keyevent_handler.cc`、`tip_edit_session_impl.cc` | アイドルタイマー → REQUEST_TYPO_SUGGESTION、パススルー IME オフキー、単語登録ダイアログ起動 |
| win32/installer、custom_action | `BUILD.bazel`、`*.wxs`、`custom_action.cc` | AzooKey DLL とリソースバンドルの同梱、Zenzai モデルの DL |
| bazel | `BUILD.azookey_dlls.bazel` | 同梱 DLL の一覧（Swift ランタイム 15 本 + llama.cpp 5 本） |

upstream 側でこの 3 か月に動いたファイルは `protocol/commands.proto`（9 コミット）と `converter/converter.cc`（7 コミット）が突出している。次回も同じ 2 ファイルから確認する。

### ARM64 の扱い

**棚上げ（凍結）**。ARM64 CI も無効化済み（`03fe68b8b`）。再開する場合は fork 独自方式ではなく、upstream の universal installer（#1434 `enable_win_universal_installer`、#1460 ARM64 ネイティブ Ninja）への乗り換えを前提に再設計する。`build-arm64.bat` は動作しないまま意図的に残している。

### rebase 手順

1. `patch-myime-next` をバックアップブランチ（`patch-myime-next-backup-<日付>`）に温存する
2. 別 worktree で `git rebase upstream/master` を実行し、衝突は上記ホットスポット表で意図を確認しながら解決する
3. `//win32/tip:tip_text_service_impl` のビルドと PR Tests の 8 テストをローカルで通す
4. push は SSH URL で行う（gh の OAuth トークンには `workflow` スコープが無く、upstream の workflow 変更を含む push が拒否される）
5. myime 側で submodule ポインタを更新し、本ドキュメントのサマリと rebase 履歴を書き換える

## 2. AzooKeyKanaKanjiConverter subtree（`windows-llama-patch`）

fork の分岐点は upstream `75c7c2b`（2025-08-26、v0.11.1 相当）。myime の subtree が最後に pull したのは fork の `ae68ff5`（2026-02-10）で、以後はローカルで直接編集し、2026-09-02 に `git subtree push` で fork へ反映した（fork 先端 `ad565e81b`）。fork と subtree の差分は 0。

### fork 独自パッチ

| 変更 | 処分 |
|---|---|
| `Package.swift`: swift-tokenizers を `unok/swift-tokenizers` の `windows-upstream-patch` ブランチ参照に、Windows 用 systemLibrary（`Sources/llama.cpp`、`-Llib/windows`）、linkerSettings | **保持**。upstream は分岐後この領域を未変更 |
| `Sources/llama.cpp/include/`: llama.cpp b4846（`fkunn1326/llama.cpp`、Zenzai トークナイザパッチ入り）のヘッダ vendoring | **保持**。llama.cpp 更新は #54 |
| `Sources/llama.cpp/llama.h`（直下）: `include/llama.h` と別世代の重複コピー（`GPT2_SMALL_JAPANESE_CHAR` が 29、`include/` 側は 30）。`llama.pc` の includedir はこちらを指す | **#49 で `include/` 側に一本化** |
| `ZenzContext.swift`、`Zenz.swift`、`ConvertRequestOptions.swift`、`KanaKanjiConverter.swift`: Windows で ggml-cpu.dll / ggml-vulkan.dll を llama.dll と同じディレクトリから明示ロード（`GGML_BACKEND_DL`）、GPU（Vulkan）のオプトインと起動時ウォームアップ | **保持**。upstream の Zenz リファクタ（#325）と `ZenzContext.swift` で衝突する（下記） |
| `DictionaryBuilder.swift`: `import Collections` → `import OrderedCollections` | upstream main と同一。追従で収束 |
| `.gitmodules`: 辞書 submodule が旧組織 `ensan-hcl/*` のまま | ルートの `.gitmodules` が実効のため実害なし。#49 で `azooKey/*` に揃える |

### llama.cpp バージョンの単一ソース化

**正準定義: `scripts/llama-cpp-version.env`**（`LLAMA_CPP_REPO` + `LLAMA_CPP_VERSION`）。CI ワークフロー・`build-x64.bat`・`scripts/ci/build-llama-cpp.bat` はすべてここを参照する。

- vendored ヘッダの出自は `fkunn1326/llama.cpp` release b4846（commit `10131b23ee`、2025-03-07）。この fork は 2025-03-10 以降更新がない
- `include/llama.h` には Zenzai 用トークナイザパッチ（`LLAMA_VOCAB_PRE_TYPE_GPT2_SMALL_JAPANESE_CHAR = 30`）が入っている。**vanilla をビルドすると zenz モデルの読み込み/トークン化が壊れる**
- `ggml-webgpu.h` 等 4 本のスタブヘッダのみ b7310 以降の世代から追加コピーされたもの（実害なし）
- 更新先候補は `azooKey/llama.cpp` の `b9637-azookey.1`（2026-07-28、同トークナイザ互換入り）。ただし upstream AKKKC の Package.swift が b4846 の xcframework を参照している間は Swift 側の API 差分を myime 単独で抱えることになるため保留（#54）

### upstream 追従計画（#49）

upstream main（2026-08-30）は分岐点から 69 コミット先。主な変更は破壊的変更 `custom(URL)` → `tableName(String)`（#298）、新辞書フォーマット（#339）、Zenz リファクタ（#325）、右文脈入力（#340）、Zenzai 高速化（#350〜#354）、Converter 共有（#353）、LM タイポ訂正（#326）。

2026-09-02 に試した `git rebase upstream/main` は 6 コミット目（`GGML_BACKEND_DL`）で `ZenzContext.swift` の 3 箇所（`WinSDK` import と `Darwin` import、`cpuBackendLoaded` ブロックと upstream の `inferenceThreadCount`、`reset_context` → `resetContext` 改名）が衝突した。コミット単位の解決は割に合わないため、**upstream main の上に Windows パッチを移植し直す**方式にする。

チェックリスト:

- [ ] `custom(URL)` → `tableName(String)`（#298）が swift-engine 側の呼び出しに影響しないか
- [ ] 新辞書フォーマット（#339）: 辞書 submodule を v3.0.1 → v3.1.0-beta.15 へ、絵文字辞書を v0.2 → v0.3 へ更新して動作確認
- [ ] Zenz リファクタ後（#325）のコードへ Windows の DLL 明示ロードと GPU オプトインを移植
- [ ] vendored `llama.h` の重複を `include/` 側に一本化し、`llama.pc` の includedir を合わせる
- [ ] subtree pull 後に `lib/windows` の DLL が復活していないか確認
- [ ] fork と subtree の差分が 0 であることを `git diff <fork tip> HEAD:src/AzooKeyKanaKanjiConverter` で確認

## 3. swift-tokenizers / swift-huggingface（fork 廃止済み、2026-06-11）

`src/swift-tokenizers/` subtree は廃止し、upstream `huggingface/swift-transformers` 系を SwiftPM のリモート依存で使う（[ADR-0002](adr/0002-retire-swift-tokenizers-fork.md)）。

- AzooKey の Package.swift → `unok/swift-tokenizers` の `windows-upstream-patch` ブランチ（upstream main `50843f9`（2026-05-19）+ 2 コミット: fnmatch シム、依存差し替え）
- その依存 → `unok/swift-huggingface` の `windows-patch` ブランチ（v0.9.0 + 1 コミット: FileLock スタブ / fnmatch シム / cachesDirectory シム、約 70 行）
- 旧ブランチ `windows-swift621-patch` は履歴として fork に残置

Windows で必要なパッチは swift-huggingface 側の 4 箇所と本体 `HubApi.swift` の 1 箇所に限られ、myime が使う API（`HubApi.shared`、`AutoTokenizer.from(tokenizerConfig:tokenizerData:)` 等）は upstream 最新でも変更なし。#50 で両 fork を upstream 先端へ rebase し、`huggingface/swift-huggingface` への Windows 対応 PR を検討する。

## 4. 関連する未 push / 未整理事項

2026-09-02 時点で未 push のローカルコミットはない。残る作業はすべて Issue #56 配下の #49〜#54 に載っている。
