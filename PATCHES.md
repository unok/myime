# Patches for Windows Swift Compatibility

> **このドキュメントは廃止されました（2026-06-11）。**
>
> ここに記載されていた swift-tokenizers の Trie.swift パッチ（Swift 6.2.1 SIL バグ回避）は、
> upstream `huggingface/swift-transformers` 最新版で不要になったことを実機検証で確認済みです。
> ローカル clone ベースのセットアップ手順も subtree / SwiftPM リモート依存への移行により無効です。
>
> 現在のパッチ状況・依存構成は以下を参照してください:
>
> - [docs/upstream-divergence.md](./docs/upstream-divergence.md) — fork/subtree のパッチ棚卸し
> - [docs/adr/0002-retire-swift-tokenizers-fork.md](./docs/adr/0002-retire-swift-tokenizers-fork.md) — swift-tokenizers fork 廃止の決定
> - [docs/architecture.md](./docs/architecture.md) — ビルド配線の全体像
