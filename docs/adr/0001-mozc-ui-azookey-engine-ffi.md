# Mozc UI + AzooKey エンジンを動的ロード C FFI で接続する

Windows の TSF/IME 層（候補ウィンドウ、キーマップ、設定ツール、インストーラ）を一から作るコストは膨大なため、実績のある Mozc を UI フレームワークとして fork し、かな漢字変換だけを AzooKey（Swift製、Zenzai AI 対応）の `azookey-engine.dll` に委譲する構成を採った。接続は C++/Swift の ABI 混在を避けるため C FFI（候補は JSON 文字列で受け渡し）とし、Mozc 側は DLL に静的リンクせず `LoadLibrary` による動的ロードにすることで、Mozc 単体のビルド・テストを DLL なしで可能にし、DLL 不在時や初期化失敗時は `engine.cc` の `NoOpImmutableConverter` に切り替えて IME 全体を落とさず変換のみ無効化できるようにした。

## Considered Options

- **純粋 Mozc**: 変換品質の改善（Zenzai のニューラル変換）が得られない
- **C# で IME を自作**: C# で TSF を直接実装する試作を 2025-12 まで行ったが、TSF 周りの成熟度で Mozc に及ばず、現在は git 履歴に残るのみで `src/csharp-ime/` は削除済み
- **AzooKey を C++ に移植**: 変換エンジンの upstream 追従が事実上不可能になる

## Consequences

- mozc fork（patch-myime）の維持と upstream rebase が恒常コストになる → 最小パッチ方針と [upstream-divergence.md](../upstream-divergence.md) で管理
- インストーラに Swift Runtime + llama.cpp の DLL 群を同梱する必要がある
