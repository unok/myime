# upstream divergence 棚卸し

fork / subtree が upstream に対して持つパッチの一覧と、各パッチの要否・処分を記録する。運用は**最小パッチ方針**（[CONTEXT.md](../CONTEXT.md) 参照: upstream 既存ファイルへの差分を最小化、新規ファイル追加は許容）に従う。

調査基準日: **2026-09-02**。upstream は動き続けるため、rebase / subtree pull のたびに本ドキュメントを更新すること。進行中の追従作業は Issue #56 にまとめている。

## サマリ

| リポジトリ | fork 独自パッチ | upstream からの遅れ | 方針 |
|---|---|---|---|
| mozc（`unok/mozc` `patch-myime-next`） | 43 コミット（+4,708/−27、67 ファイル） | **0**（2026-09-02 に `4b1953a93`（2026-08-27）へ rebase 済み） | 定期追従。次回の衝突箇所は §1 |
| AzooKeyKanaKanjiConverter（`unok/AzooKeyKanaKanjiConverter` `windows-llama-patch`） | 2 コミット（vendored ヘッダ + Windows 対応、Swift 4 ファイル） | **0**（2026-09-02 に upstream main `93766c4`（2026-08-02）の上へ移植し直し） | 定期追従。移植の要点は §2 |
| swift-tokenizers（`unok/swift-tokenizers` `windows-upstream-patch`） | 2 コミット | **0** | 定期追従 |
| swift-huggingface（`unok/swift-huggingface` `windows-patch`） | 2 コミット | **0** | 定期追従 |
| EventSource（`unok/EventSource` `windows-patch`） | 1 コミット（3 行） | **0**（基点 1.5.1） | Swift 6.3.x のコンパイラ不具合の回避。upstream で解消したら廃止 |

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
| converter | `azookey_immutable_converter.cc/.h`（新規）、`azookey_candidate_parser.cc/.h` + `_test.cc`（新規）、`azookey_user_dictionary.cc/.h`（新規） | AzooKey DLL のロード（bazel test 文脈では `MYIME_AZOOKEY_DLL_DIR` で配置先指定）、JSON 候補のパースとセグメント展開（DLL 非依存のライブラリとテスト）、Mozc ユーザー辞書の AzooKey へのプッシュ |
| converter | `engine_config.h` | レジストリ読み取り（ZenzaiEnabled / ZenzaiUseGpu / TypoCorrectionEnabled / IdleResuggest / TypoCorrectionUseAi / パススルーキー）とモデルパス探索。`MYIME_HERMETIC_TEST=1` で hermetic test-mode（レジストリ・モデル探索を無視、学習データを `TEST_TMPDIR` へ、bazel test から `--test_env` で渡す） |
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

fork `windows-llama-patch` は 2026-09-02 に upstream main `93766c4`（2026-08-02）の上へ作り直した（先端 `bd6d5b8`、旧先端 `ad565e81b` はブランチ `windows-llama-patch-backup-20260902` に温存）。myime の subtree は同日に `git subtree pull --squash` で取り込み、fork と subtree の差分は 0（squash コミットの `git-subtree-split: bd6d5b8`）。

### fork 独自パッチ（2 コミット）

| 変更 | 内容 |
|---|---|
| `chore: vendor fkunn1326/llama.cpp b4846 headers` | `Sources/llama.cpp/include/`（Zenzai トークナイザパッチ入り b4846、myime が DLL をビルドしている世代。由来は同ディレクトリの README.md）と `module.modulemap`（`include/llama.h` のみ）。upstream 直下の `llama.h`（`GPT2_SMALL_JAPANESE_CHAR = 29` の別 fork 世代）は upstream のファイルなので触らない。実ビルドでは modulemap 経由で `include/` 側だけが使われる。旧 fork にあった `llama.pc` / `llamacpp.pc` は `pkgConfig:` 未宣言で誰にも読まれていなかったため削除 |
| `feat: Windows/llama.cpp support on upstream main` + `fix: pass a CPU-only device list ...` | `Package.swift`（swift-tokenizers を `unok/swift-tokenizers` の `windows-upstream-patch` に、Windows/Linux の `llama` systemLibrary、Windows 向け linkerSettings は `Context.packageDirectory` 基準で cwd 非依存）、`ZenzContext.swift`（`loadGgmlBackend` で llama.dll と同じディレクトリから ggml-cpu.dll / ggml-vulkan.dll を明示ロードし `ensureBackendsLoaded()` でトリガーを明示、`createContext(path:useGpu:)` の Vulkan オプトイン、CPU 経路とフォールバックでは NULL 終端の CPU-only デバイスリストを渡す（`n_gpu_layers = 0` だけでは Vulkan 登録済みプロセスでデバイスが列挙される）、upstream の共有モデルキャッシュのキーに GPU モードを追加）、`Zenz.swift` / `ConvertRequestOptions.swift` / `KanaKanjiConverter.swift`（`useGpu` の伝播） |

fork 版にあった「モデルとコンテキストを ZenzContext が直接所有して解放・再ロードする」実装は、upstream が共有モデルキャッシュへ分離したため移植せず、キャッシュキーへの GPU モード追加と GPU 失敗時の CPU モデルへの切替で同等の挙動にした。`.gitmodules` の辞書 URL が旧組織 `ensan-hcl/*` なのは upstream も同じで、GitHub のリダイレクトで解決するため触らない。

### llama.cpp バージョンの単一ソース化

**正準定義: `scripts/llama-cpp-version.env`**（`LLAMA_CPP_REPO` + `LLAMA_CPP_VERSION`）。CI ワークフロー・`build-x64.bat`・`scripts/ci/build-llama-cpp.bat` はすべてここを参照する。

- vendored ヘッダの出自は `fkunn1326/llama.cpp` release b4846（commit `10131b23ee`、2025-03-07）。この fork は 2025-03-10 以降更新がない
- `include/llama.h` には Zenzai 用トークナイザパッチ（`LLAMA_VOCAB_PRE_TYPE_GPT2_SMALL_JAPANESE_CHAR = 30`）が入っている。**vanilla をビルドすると zenz モデルの読み込み/トークン化が壊れる**
- `ggml-webgpu.h` 等 4 本のスタブヘッダのみ b7310 以降の世代から追加コピーされたもの（実害なし）
- 更新先候補は `azooKey/llama.cpp` の `b9637-azookey.1`（2026-07-28、同トークナイザ互換入り）。ただし upstream AKKKC の Package.swift が b4846 の xcframework を参照している間は Swift 側の API 差分を myime 単独で抱えることになるため保留（#54）

### 2026-09-02 の追従（#49）で吸収した upstream 変更

旧分岐点 `75c7c2b`（2025-08-26、v0.11.1 相当）から main `93766c4` までの 69 コミット。破壊的変更 `custom(URL)` → `tableName(String)`（#298）、新辞書フォーマット（#339、辞書 submodule は v3.0.1 → v3.1.0-beta.15、絵文字辞書は v0.2 → v0.3）、Zenz リファクタ（#325）、右文脈入力（#340）、Zenzai 高速化（#350〜#354）、Converter 共有（#353）、LM タイポ訂正（#326）。

コミット単位の `git rebase upstream/main` は `ZenzContext.swift` の 3 箇所（`WinSDK` / `Darwin` import、`cpuBackendLoaded` と upstream の `inferenceThreadCount`、`reset_context` → `resetContext` 改名）で衝突したため、upstream main の上に Windows パッチを移植し直した。myime 側（`src/swift-engine`）で必要だった追従は 2 点。`ConvertRequestOptions` の `requireJapanesePrediction` / `requireEnglishPrediction` が Bool から `PredictionMode`（`.autoMix` / `.disabled`）に変わったこと（2 行）と、予測候補（入力より長い読み）の `value` が変換候補と別スケールになったこと（実測: 「ほにゃらら」が −19.5 → −2.1、「京都府」が −12.0 → +1.2。入力全体をカバーする候補の値は −11.5 → −11.8 程度でほぼ不変）。後者はタイポ補正パスの「1 パス目最良との 1 モーラあたり比較」を狂わせ、本屋・京都の補正候補が消えたため、比較対象から入力より長い予測候補（`rubyCount > key.count`）を外した（`TypoCorrectionPass.swift`）。接頭辞断片は変換候補と同じスケールでマージンが断片込みで校正されているため残す（入力全体をカバーする候補だけにすると「がっこう」に顎骨が誤検出される）。辞書 v3.1 で基準側の断片「が」の値が −1.48 → −1.79 に下がり、顎骨（差分 −1.95）が旧マージン −2.0 を通り抜けたため、マージンを −1.8 に詰めた（真の補正の実測最悪 −1.66 との余裕 0.14）。再校正用に環境変数 `AZOOKEY_TYPO_DEBUG` で候補の値を stderr に出す診断出力を追加した。upstream が追加した `typoCorrectionMode` は既定の `.automatic`（Windows では無効）のままで、旧 `needTypoCorrection` のプラットフォーム既定と同じ挙動。myime 独自のタイポ補正（`TypoCorrectionPass.swift`）はこの設定と独立に動く。

次回の追従手順: fork の clone で `windows-llama-patch` を upstream main に rebase（衝突は上記 2 コミットの範囲に限られる）→ `swift build` で確認 → SSH で force-with-lease push → myime で `git subtree pull --squash`（前回 pull 以降にローカルで subtree を直接編集していると衝突する。その場合は squash コミットのツリーで `src/AzooKeyKanaKanjiConverter` を丸ごと置き換える。`git rm -r` は `.gitmodules` の辞書エントリを消すので復元すること）→ 辞書 submodule を `git submodule update --init` → `swift build` / `swift test`（PATH に `lib/windows`）。

## 3. swift-tokenizers / swift-huggingface

`src/swift-tokenizers/` subtree は廃止し、upstream `huggingface/swift-transformers` 系を SwiftPM のリモート依存で使う（[ADR-0002](adr/0002-retire-swift-tokenizers-fork.md)）。

- AzooKey の Package.swift → `unok/swift-tokenizers` の `windows-upstream-patch` ブランチ。基点は `huggingface/swift-transformers` main（1.3.3 以降）。差分は 2 コミット（fnmatch シム、swift-huggingface フォークへの依存差し替え）
- その依存 → `unok/swift-huggingface` の `windows-patch` ブランチ。基点は `huggingface/swift-huggingface` main（0.10.0）。差分は 1 コミット（FileLock スタブ、fnmatch シム、cachesDirectory シム）
- 旧ブランチ `windows-swift621-patch` は履歴として fork に残置
- swift-huggingface の依存 EventSource → `unok/EventSource` の `windows-patch` ブランチ（基点 `mattt/EventSource` 1.5.1）。差分は 1 コミット 3 行: `waitForLinuxCompletion()` の `CheckedContinuation` を `UnsafeContinuation` に置換。Windows の swift-frontend 6.3.3（+Asserts）が同関数の IR 生成で `Cannot dereference a null Type!` のアサーションで落ちるための回避で、6.2.1 では不要だった（2026-09-03、#50）。upstream の EventSource か Swift 側で解消したら fork を廃止し `mattt/EventSource` に戻す

両 fork は 2026-09-02 に upstream 先端へ rebase 済み。swift-tokenizers の衝突は `Package.swift` の swift-jinja 2.4.2 行のみで、旧先端は `windows-upstream-patch-backup-20260902` に保存した。swift-huggingface は衝突なしで、旧先端は `windows-patch-backup-20260902` に保存した。

Windows で必要なパッチは swift-huggingface 側の FileLock スタブ・fnmatch シム・cachesDirectory シムと、swift-tokenizers 側の fnmatch シム・依存差し替えに限られる。myime が使う API（`HubApi.shared`、`AutoTokenizer.from(tokenizerConfig:tokenizerData:)` 等）は upstream 最新でも変更なし。`huggingface/swift-huggingface` への Windows 対応 PR を検討する。

## 4. 関連する未 push / 未整理事項

2026-09-02 時点で未 push のローカルコミットはない。残る作業はすべて Issue #56 配下の #49〜#54 に載っている。
