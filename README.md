# MyIME

Windows向け日本語IME。MozcのUIフレームワーク（fork）とAzooKeyのかな漢字変換エンジンをC FFIで接続し、LLM変換（Zenzai）・タイポ補正・辞書登録候補を加えたハイブリッド構成。

```
┌─────────────────────────────────────────────────┐
│                   Mozc (UI)                      │
│  - TSF/IME フレームワーク                        │
│  - 候補ウィンドウ・設定ツール                    │
└─────────────────┬───────────────────────────────┘
                  │ C FFI
┌─────────────────▼───────────────────────────────┐
│           azookey-engine.dll (Swift)            │
│  - AzooKeyKanaKanjiConverter                    │
│  - Zenzai AI (llama.cpp)                        │
└─────────────────────────────────────────────────┘
```

ビルド手順は [docs/build.md](docs/build.md)、内部構造は [docs/architecture.md](docs/architecture.md) を参照。

## インストール

`Mozc_x64.msi` を管理者権限で実行する。MSI は [docs/build.md](docs/build.md) の手順でビルドするか、GitHub Actions「Build x64」の成果物を使う。

インストール時に Zenzai のモデル（約500MB）が自動ダウンロードされる。失敗してもインストールは続行し、モデルは後から追加できる（下記「Zenzai」参照）。アンインストールは Windows の「設定」→「アプリ」→「Mozc」から。

## 標準の IME にない機能

### Zenzai（LLM かな漢字変換）

llama.cpp 上のニューラル言語モデル zenz-v3.1-small（約500MB）で変換候補を生成・評価する。モデルファイルがあり設定がオン（既定）なら自動で有効になり、なければ通常の辞書変換だけで動く。推論は既定で CPU。設定で Vulkan GPU に切り替えられる（対応 GPU とドライバが必要）。

モデルの入手方法は3つ:

- MSI インストール時の自動ダウンロード
- `mozc_tool --mode=zenzai_download`（モデル未検出時に IME が案内を出す）
- 手動配置:

  ```cmd
  mkdir "%LOCALAPPDATA%\Mozc\models"
  curl -L -o "%LOCALAPPDATA%\Mozc\models\ggml-model-Q5_K_M.gguf" ^
    "https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf"
  ```

### タイポ補正

ローマ字の打鍵ミスを補正した候補をスペース変換時に追加する。「gakou」→「学校」のような1文字欠け、「ありがとうございまs」のようにアルファベットが残った入力、長文の途中に紛れたタイポを扱う。補正候補は通常変換とは独立した2パス目で生成されるため、正しく打てた入力の変換結果は変わらない。

### アイドル再サジェスト（既定オフ）

入力が止まって約0.4秒後に、予測窓へタイポ補正込みの候補を追加する。打鍵中は何もしないため入力遅延はない。

### 辞書登録候補と単語登録

予測窓・変換窓の末尾に【辞書登録】候補が常に表示される。選んでも文字列は確定されず、入力中の文字列を取り消したうえで単語登録ダイアログが開く。読みは事前入力される（予測窓では入力中のひらがな全体、変換窓ではフォーカス中の文節の読み）。未入力の状態からは Ctrl+F7 でも開ける（MS-IME キーマップ）。

登録した単語は保存した時点で AzooKey 変換（予測・Zenzai 含む）にも反映される。正本は Mozc のユーザー辞書で、AzooKey へは一方向に全量プッシュする（[ADR-0003](docs/adr/0003-mozc-user-dictionary-as-source-of-truth.md)）。

## 設定

通知領域の Mozc アイコンのメニューから「プロパティ」を開き、Conversion engine グループで切り替える。実体は `HKCU\Software\Mozc` のレジストリ値で、`reg add` での直接変更もできる。

| 設定 | レジストリ値 | 既定 | 内容 |
|---|---|---|---|
| Zenzai | `ZenzaiEnabled` | オン | LLM による変換（モデルがある場合のみ） |
| GPU (Vulkan) | `ZenzaiUseGpu` | オフ | Zenzai の推論を GPU で行う |
| タイポ補正 | `TypoCorrectionEnabled` | オン | 打鍵ミスの補正候補を表示 |
| アイドル再サジェスト | `IdleResuggest` | オフ | 入力停止時に予測窓へ補正候補を追加 |
| タイポ補正の AI 評価 | `TypoCorrectionUseAi` | オフ | 補正候補の評価に Zenzai を使う（変換時のみ・低速） |
| パススルー IME オフキー | `PassthroughImeOffModifiers` / `PassthroughImeOffKeys` | （空） | キーをアプリへ渡しつつ IME をオフにする（下記） |

```cmd
:: 例: アイドル再サジェストを有効化
reg add HKCU\Software\Mozc /v IdleResuggest /t REG_DWORD /d 1 /f
```

### パススルー IME オフキー

設定したキー（例: Ctrl+T）を押すと、キーはアプリにそのまま届き、同時に IME がオフ（直接入力）になる。tmux などのプレフィックスキーの後続入力が IME に食われなくなる。

設定ダイアログの「Passthrough IME-off keys」で、修飾キーをチェックボックス（Ctrl / Alt / Shift）で選び、「Keys」欄にキーをスペースまたはカンマ区切りで並べる。例えば Ctrl にチェックを入れて `T, Q` と書くと Ctrl+T と Ctrl+Q が対象になる。書式が不正なとき（英数字1文字でないキー、修飾キー未選択）は適用時にエラーを表示して保存しない。キー欄を空にすると機能オフ。

レジストリで直接設定する場合は2つの値を書く。

```cmd
reg add HKCU\Software\Mozc /v PassthroughImeOffModifiers /t REG_SZ /d "Ctrl" /f
reg add HKCU\Software\Mozc /v PassthroughImeOffKeys      /t REG_SZ /d "T Q" /f
```

- 設定した全キーが同じ動作で、押すと IME をオフにする（トグルではない）。オフの状態は持続し、日本語入力に戻すのは通常の切替キー（半角/全角など）で行う
- 修飾キーは全キー共通。キーごとに別の修飾キーを割り当てることはできない
- キーの大文字小文字は区別しない（`t` と `T` は同じ）。Shift を押す必要があるかは Shift のチェックだけで決まり、修飾キーは完全一致で判定する。例えば Ctrl のみのとき Ctrl+Shift+T では発動しない
- IME オンかつ未確定文字列がないときだけ発動する。設定変更は次のキー入力から反映される（IME 再起動不要）

## トラブルシューティング

### IME が表示されない

1. コンピュータを再起動
2. 「設定」→「時刻と言語」→「言語と地域」→「日本語」→「言語オプション」で Mozc を追加

### Zenzai が動作しない

- モデルファイルが `%LOCALAPPDATA%\Mozc\models\` か `%ProgramFiles(x86)%\Mozc\models\` にあるか確認
- 設定ダイアログで Zenzai が有効か確認（既定は有効）
- GPU 設定を有効にしている場合は Vulkan 対応 GPU とドライバが必要。動かない場合は GPU 設定を外せば CPU で動く

### インストールが遅い・変更が反映されない

- IME の DLL は起動中の全アプリに読み込まれるため、アプリを多く開いているとインストールに数分かかる（閉じてから実行すると速い）
- インストールが「再起動が必要」で終わった場合、再起動するまで古い DLL が動き続ける。新機能が反映されない時はまず再起動する
- 起動済みのアプリは再起動するまで古い DLL を使い続ける。動作確認は新しく開いたアプリで行う

ビルド関連のトラブルは [docs/build.md](docs/build.md) を参照。

## ドキュメント

- [docs/build.md](docs/build.md) — ビルド環境・手順・開発時の再インストール
- [docs/architecture.md](docs/architecture.md) — Mozc ⇔ AzooKey 統合の内部構造
- [docs/adr/](docs/adr/) — 設計判断の記録
- [docs/upstream-divergence.md](docs/upstream-divergence.md) — fork / subtree が upstream に対して持つパッチの棚卸し
- [CONTEXT.md](CONTEXT.md) — プロジェクト用語集

## ライセンス

- MyIME: MIT License
- Mozc: BSD 3-Clause License
- AzooKeyKanaKanjiConverter: MIT License
- llama.cpp: MIT License

## 参考

- [Mozc](https://github.com/google/mozc) - Google 日本語入力のオープンソース版
- [AzooKeyKanaKanjiConverter](https://github.com/ensan-hcl/AzooKeyKanaKanjiConverter) - かな漢字変換エンジン
- [azooKey-Windows](https://github.com/fkunn1326/azooKey-Windows) - Windows 移植の参考
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - LLM 推論エンジン
