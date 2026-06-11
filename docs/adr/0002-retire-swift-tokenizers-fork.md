# swift-tokenizers fork を廃止し upstream + swift-huggingface 小パッチへ移行する

`unok/swift-tokenizers` fork（subtree `src/swift-tokenizers/`）の存在理由は「upstream（huggingface/swift-transformers）が Windows + Swift 6.2.1 で直接コンパイルできなかった」ことだったが、2026-06-11 の実機検証で主因のコンパイラクラッシュ（Trie.swift の SIL エラー）が upstream 最新（`50843f9`）で解消済みと確認した。残るブロッカーは依存先 swift-huggingface v0.9.0 の4箇所（POSIX 専用 FileLock、`fnmatch`×3、`URL.cachesDirectory`）+ 本体の `fnmatch` 1箇所のみで、計約70行のパッチでフルビルドが通る。よって15ヶ月遅れの fork（9コミットのミニマル化パッチ）を維持するのをやめ、upstream 最新 + swift-huggingface への小パッチに移行する。myime が使う API（`HubApi.shared`、`configuration(fileURL:)`、`AutoTokenizer.from` 等）は新版に全て健在で、利用側コードの変更は不要。

Status: accepted（移行作業は別タスク。完了まで現 fork は凍結のまま使用）

## Consequences

- パッチ対象が swift-transformers 本体から swift-huggingface に移る。`huggingface/swift-huggingface` へ Windows 対応 PR が採用されれば完全 fork レス化が可能
- myime の利用経路（ローカルファイル読み込み）は FileLock を通らないため、FileLock はスタブで実用上問題ない
- 移行手順の詳細は [upstream-divergence.md §3](../upstream-divergence.md) を参照
