# MyIME

Windows向け日本語IME。Mozc のUIフレームワーク（fork）と AzooKey のかな漢字変換エンジン（Zenzai AI対応）を C FFI で接続するハイブリッド構成。upstream への追従コストを抑えるため、外部リポジトリへの介入度合いを用語として明確に区別する。

## Language

### リポジトリ運用

**最小パッチ方針**:
fork・subtree では upstream の既存ファイルへの差分を最小化する方針。新規ファイルの追加は rebase で衝突しないため許容し、適応ロジックは可能な限り myime 側に置く。
_Avoid_: 最小限の修正（「何が最小か」が曖昧なため）

**upstream**:
fork・subtree の追従元となる本家リポジトリ（google/mozc, azooKey/AzooKeyKanaKanjiConverter, huggingface/swift-transformers）。
_Avoid_: 本家、オリジナル

**fork**:
upstream に対する unok 名義の派生リポジトリ。myime 用パッチをブランチ（patch-myime 等）で保持する。

**陳腐化パッチ**:
fork に存在するが、upstream の更新により本来不要になった（または upstream の新方式に置き換えるべき）パッチ。rebase 時に破棄候補となる。
_Avoid_: 不要な修正、古いパッチ

**独立バグ修正**:
fork に含まれるが AzooKey 統合とは無関係な、upstream 自体のバグへの修正。保持しつつ upstream への PR 候補として扱う。
_Avoid_: ついで修正

### 変換エンジン

**Zenzai**:
llama.cpp 上で動くニューラル言語モデルにより変換候補を再評価する AzooKey の AI 変換機能。モデルファイル（GGUF）の存在だけで自動的に有効化される。

**correspondingCount**:
1つの変換候補がカバーする読み（ひらがな）の文字数。バイト数ではない。Mozc 側の consumed_key_size の算出元。
_Avoid_: 消費バイト数

### ユーザー辞書と単語登録

**ユーザー辞書**:
ユーザーが登録した単語の集合。Mozc 形式の辞書を正本とし、AzooKey 変換には動的ユーザー辞書として反映される。
_Avoid_: 学習辞書（AzooKey の変換学習 = memory とは別物）

**動的ユーザー辞書**:
AzooKey エンジンがメモリ上に保持する追加語彙。ユーザー辞書の内容を変換候補に効かせるための受け皿で、それ自体は永続化されない。

**辞書登録候補**:
予測窓・変換窓の末尾に常に表示される特殊候補。選択しても文字列は確定されず、未確定文字列を取り消した上で単語登録ダイアログが開く。
_Avoid_: 辞書登録コマンド

**単語登録ダイアログ**:
読み・単語・品詞を入力してユーザー辞書に1語追加する Mozc 付属の GUI。辞書登録候補から開くと読みが事前入力される（予測窓では入力中のひらがな全体、変換窓ではフォーカス中の文節の読み）。
_Avoid_: 辞書登録ダイアログ
