このディレクトリは fkunn1326/llama.cpp b4846 のヘッダです（Zenzai トークナイザパッチ入り、myime の Windows DLL をビルドしている世代）。
`module.modulemap` はこのディレクトリだけを参照します。
トップレベルの `llama.h` / `ggml*.h` は upstream azooKey 由来の別世代で、Windows/Linux ビルドでは使われません。
`-I` を追加して別世代のヘッダを参照させないでください。
