# upstream divergence 棚卸し

fork / subtree が upstream に対して持つパッチの一覧と、各パッチの要否・処分を記録する。運用は**最小パッチ方針**（[CONTEXT.md](../CONTEXT.md) 参照: upstream 既存ファイルへの差分を最小化、新規ファイル追加は許容）に従う。

調査基準日: **2026-06-11**。upstream は動き続けるため、rebase / subtree pull のたびに本ドキュメントを更新すること。

## サマリ

| リポジトリ | fork独自パッチ | upstreamからの遅れ | 方針 |
|---|---|---|---|
| mozc (`unok/mozc` patch-myime) | 12コミット (+2315/-88, 33ファイル) | 303コミット (~5.5ヶ月) | 計画的 rebase（文節調整開発が一段落後） |
| AzooKeyKanaKanjiConverter (`unok/AzooKeyKanaKanjiConverter` windows-llama-patch) | 実質1コミット | 64コミット (~9ヶ月) | 追従を計画 |
| swift-tokenizers (`unok/swift-tokenizers` windows-swift621-patch) | 9コミット | 128コミット (~15ヶ月) | **fork 廃止へ移行**（下記） |

## 1. mozc fork（patch-myime → **patch-myime-next に rebase 済み、2026-06-12**）

**2026-06-12 に upstream/master（`fea1ebace`, 2026-06-11時点）へ rebase 完了。** 新ブランチ `patch-myime-next`（旧 `patch-myime` はバックアップタグ `patch-myime-backup-20260612` とともに温存。master マージ時に改名予定）。

rebase 結果: fork 独自コミットは **14 → 11** にスリム化（27ファイル, +2272/-15 程度）。

- 破棄した陳腐化パッチ: rules_cc/rules_python バンプ、ARM64 関連2件（棚上げ）、**rules_swift 3.4.1 pin（rules_apple 4.5.2 が 3.5.0 を要求するため不要化）**、.bazelrc の32bitツールチェーン削除（upstream の x86 パッチ復活と整合させ撤回）
- 破棄したノイズ: converter.cc の LOG、session.cc/engine_converter.cc/win32_ipc.cc の実質無変更・トレース
- 破棄した暫定対応: wxs の Windows バージョンチェック無効化（upstream の条件 build≥17763 は Insider でも通過するため不要）
- 新規追従対応: `ImmutableConverterInterface::Convert` の **ConversionOptions API 移行**（旧 ConversionRequest、実装は引数未使用のため機械的置換）
- installer は upstream の universal installer 対応構造（単一 genrule + `build_msi`）に移行し、AzooKey DLL/リソースバンドル/`--azookey_dll_dir` をグラフト。**upstream が build_installer→build_msi 改名で UAC インストーラ検出問題を解決済み**（myime 側の RunAsInvoker 回避は無害だが原理的に不要に）
- 検証: `Mozc_x64.msi` 生成成功（2026-06-12、Bazel 9.0.2）

以下は rebase 前（2026-06-11 調査時点）の記録。

分岐点: `348a49c71`（2025-12-25）。upstream/master は `9afbd9860` まで進行。

### パッチ一覧と処分

| コミット | 内容 | 処分 |
|---|---|---|
| `221c3fdf3` | AzooKey + Zenzai 統合本体（azookey_immutable_converter 等、新規867行） | **保持**（コア） |
| `49a4fea78` | Zenzai ダウンロードダイアログを手動案内UIに変更 | **保持** |
| `ab4453b7f` | 新 JSON 候補フォーマット対応 | **保持** |
| `da0f87049` | NoOpImmutableConverter 追加・ggml-vulkan.dll 対応 | **保持** |
| `e6ee4446d` | MSI インストール時の Zenzai モデルダウンロード（CustomAction） | **保持**（rebase 時 upstream #1500 と衝突確実 → 再実装前提） |
| `7df872d77` | 未使用 llava_shared.dll / mtmd.dll をインストーラから削除 | **保持** |
| `8fbddcbbb` | MSI ファイル名を `Mozc_X64.msi` / `Mozc_ARM64.msi` に統一 | **保持**（ARM64 部分は棚上げに合わせ縮小可） |
| `311117f40` | デバッグログ削除・renderer/IPC ログ更新 | 整理対象（バグ修正部分のみ残す） |
| `c14f6b850` | ARM64 MSI ビルドサポート | **破棄候補**（ARM64 棚上げ） |
| `951fa5ecd` | `.bazelrc` の windows-arm64 プラットフォーム名修正 | **破棄候補**（ARM64 棚上げ） |
| `80854da29` | rules_python 1.7.0 | **破棄**（陳腐化: upstream は 1.9.0） |
| `9ad5c5153` | rules_cc 0.2.16 | **破棄**（陳腐化: upstream は 0.2.17） |

### ファイル単位の処分（コミット横断）

| 変更 | 分類 | 処分 |
|---|---|---|
| `ipc/ipc_path_manager.cc`: IPC キー生成を SHA1(SID) からランダム16バイトに修正 | 独立バグ修正 | **保持**。upstream は現在も SHA1(SID) 方式のまま（2026-06-11 確認）→ **upstream PR 候補**。rebase 時は #1515（Singleton除去）との衝突に注意 |
| `renderer/renderer_client.cc`: renderer 再起動時の IPC パスキャッシュ Clear | 独立バグ修正 | **保持**・upstream PR 候補 |
| `converter/converter.cc`: ResizeSegment への大量 LOG(INFO)（機能変更なし） | ノイズ | **次回 rebase で破棄** |
| `session/session.cc` / `engine_converter.cc`: include追加・整形のみ（実質無変更） | ノイズ | **次回 rebase で破棄** |
| `ipc/win32_ipc.cc`: OutputDebugStringA トレース | ノイズ | **次回 rebase で破棄** |
| `installer_oss_64bit.wxs`: Windows バージョンチェックのコメントアウト（Insider対応） | 暫定対応 | rebase 時に要否再評価 |

### ARM64 の扱い

**棚上げ（凍結）**。直近で ARM64 CI も一時無効化済み（`03fe68b8b`）。ARM64 関連パッチ（`c14f6b850`, `951fa5ecd`, `.bazelrc` の `windows_arm64` config, `installer_arm64` genrule 分割, `@azookey_dlls_arm64`）はすべて破棄候補。再開する場合は fork 独自方式ではなく、upstream に新設された **universal installer**（#1434 `enable_win_universal_installer`, #1460 ARM64ネイティブ Ninja）への乗り換えを前提に再設計する。

### rebase 手順（実施時のガイド）

1. ノイズ（converter.cc ログ, session.cc 等, win32_ipc.cc トレース）と陳腐化パッチ（rules_cc / rules_python）、ARM64 関連を破棄
2. 独立バグ修正（ipc_path_manager / renderer_client）を upstream 新コード（#1515 Singleton 除去後）に合わせて再適用 — 可能なら upstream へ PR
3. AzooKey 統合（新規ファイル群）はそのまま載る見込み。既存ファイル側の接点（engine.cc, MODULE.bazel, installer BUILD/wxs, custom_action）は upstream #1500（COM 登録の CustomAction 化）後の構造に合わせて再適用
4. 衝突ホットスポット: `win32/installer/*`, `custom_action.cc`, `ipc_path_manager.cc`, `MODULE.bazel`

## 2. AzooKeyKanaKanjiConverter subtree（windows-llama-patch）

分岐点: `75c7c2b`（2025-08-26）。fork 独自は実質 `6162af9` の1コミット（Swift ソース変更ゼロ）。

### パッチ一覧と処分

| 変更 | 処分 |
|---|---|
| `Package.swift`: swift-tokenizers をローカルパス参照に変更、Windows 用 linkerSettings（llama/ggml系 + `-Llib/windows`）、systemLibrary 名変更 | **保持**（upstream は分岐後この領域を未変更 = 全パッチ依然必要）。ただし swift-tokenizers 廃止移行（§3）に伴い参照先を変更予定 |
| `Sources/llama.cpp/include/`: llama.cpp ヘッダ vendoring（2025年後半世代） | **保持**。ただし llama.cpp バージョン単一ソース化（下記）に合わせて出自バージョンを特定・固定する |
| `lib/windows/` ビルド済み DLL/LIB（約28MB）のコミット | **fork から削除する**。ローカルの削除コミット `22cde1055` を `git subtree push` で fork に反映する（CI・build-x64.bat ともソースビルドの仕組みあり。未反映のまま subtree pull すると DLL が復活するので注意） |
| `Package-patched.swift`（204行） | **削除**。どこからも参照されていない実験的残骸 |

### llama.cpp バージョンの単一ソース化（2026-06-11 実施済み）

**正準定義: `scripts/llama-cpp-version.env`**（`LLAMA_CPP_REPO` + `LLAMA_CPP_VERSION`）。CI ワークフロー・`build-x64.bat`・`run-ci-build.bat`・`scripts/ci/build-llama-cpp.bat` はすべてここを参照する。

調査で確定した事実:

- vendored ヘッダの出自は **`fkunn1326/llama.cpp` release `b4846`**（commit `10131b23ee`）。blob 一致18/22ファイルで確認
- `llama.h` には **Zenzai 用トークナイザパッチ1行**（`LLAMA_VOCAB_PRE_TYPE_GPT2_SMALL_JAPANESE_CHAR = 30`）が入っており、出自は vanilla ではなく azooKey 系 fork。**vanilla をビルドすると zenz モデルの読み込み/トークン化が壊れる**
- 修正前は CI=`b4500`(vanilla) / bat=`b4547`(vanilla) / ヘッダ=b4846(パッチ入り) と3分裂しており、ソースビルド経路で生成された DLL は Zenzai が機能しない恐れがあった
- `ggml-webgpu.h` 等4本のスタブヘッダのみ b7310 以降の世代から追加コピーされたもの（実害なし）

将来 llama.cpp を更新する場合は、fork（パッチ入り）の新タグを用意してから `llama-cpp-version.env` を書き換えること。

### upstream 追従計画

追従を予定（時期未定の別タスク）。fork は Swift ソースを触っていないため衝突は `Package.swift` / `.gitignore` / `Sources/llama.cpp` 程度に限られる。主な恩恵: Zenzai 右文脈対応 (#340)、zenz 入力予測 (#320/#322)、LM タイポ訂正 (#326)、新辞書 (#339)、学習更新クラッシュ修正 (#290)、予測キャッシュ修正 (#333)。

追従時チェックリスト:

- [ ] **破壊的変更**: `custom(URL)` API 廃止 → `tableName(String)` 統一 (#298) が swift-engine 側の呼び出しに影響しないか
- [ ] 新辞書フォーマット (#339): 辞書 submodule を `1fee663` → `4d41852` 以降へ更新し動作確認
- [ ] Zenz リファクタリング後 (#325) のコードと vendored llama.cpp ヘッダ/DLL 世代の整合（upstream は b4846 前提）
- [ ] subtree pull 後に `lib/windows` の DLL が復活していないか確認

## 3. swift-tokenizers subtree（windows-swift621-patch）→ 廃止済み（2026-06-11 移行完了）

**決定・実施（2026-06-11）: fork / subtree を廃止し、upstream `huggingface/swift-transformers` 最新版へ移行した。**

移行後の構成:

- `src/swift-tokenizers/` subtree は削除済み
- AzooKey の Package.swift → `unok/swift-tokenizers` の **`windows-upstream-patch`** ブランチ（upstream main `50843f9` + 2コミット: fnmatchシム + 依存差し替え）
- swift-transformers の依存 → `unok/swift-huggingface` の **`windows-patch`** ブランチ（v0.9.0 + 1コミット: FileLockスタブ / fnmatchシム / cachesDirectoryシム）
- 旧ブランチ `windows-swift621-patch` は履歴として fork に残置（削除しない）
- 副作用: 依存解決で swift-collections が 1.3.0→1.6.0 に上がり、`DictionaryBuilder.swift` の `import Collections` を `import OrderedCollections` に修正（upstream azooKey/main と同一の修正のため将来の追従で収束）
- 検証: `swift build -c release --arch x86_64` で azookey-engine.dll 生成を確認済み

根拠（Windows 実機での upstream 最新 `50843f9` ビルド検証結果）:

- fork の主因だった Swift 6.2.1 コンパイラクラッシュ（Trie.swift の SIL エラー）は**解消済み**（再現せず）
- 残るブロッカーは本体ではなく依存の **swift-huggingface v0.9.0 側に4箇所**（POSIX 専用 `FileLock.swift`、`fnmatch` ×3、`URL.cachesDirectory`）+ 本体 `HubApi.swift` の `fnmatch` 1箇所。計約70行のパッチで**フルビルド成功を確認済み**
- myime が使う API（`HubApi.shared`, `configuration(fileURL:)`, `AutoTokenizer.from(tokenizerConfig:tokenizerData:)`, `encode`/`decode`/`bosTokenId`/`eosTokenId`）は**新版にすべて健在、利用側コード変更不要**
- myime の利用経路（ローカルファイル読み込み）は FileLock を通らないため、FileLock はスタブで実用上問題なし

移行手順（別タスク）:

1. swift-huggingface への Windows パッチ（~70行: FileLock スタブまたは LockFileEx 実装、fnmatch シム、cachesDirectory 代替）を用意 — fork または SwiftPM 上の参照差し替え
2. AzooKey subtree の `Package.swift` をローカルパス `../swift-tokenizers` から upstream 参照へ変更
3. `src/swift-tokenizers/` subtree を削除
4. 並行して `huggingface/swift-huggingface` へ Windows 対応 PR を検討（採用されれば完全 fork レス化）

移行完了までは現 fork を凍結のまま使用する（追加パッチは入れない）。

## 4. 関連する未 push / 未整理事項

- AzooKey subtree: ローカルコミット `22cde1055`（DLL 削除）が fork 未 push（§2 参照）
- mozc fork: 直近のローカル開発と CI の整合は `build-x64.bat` 系スクリプトの master 反映で解消済み（2026-06-11 pull）
