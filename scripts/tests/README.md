# Typo correction tests

Swift generator tests:

```powershell
cd src/swift-engine
$env:Path += ";$(Resolve-Path ..\AzooKeyKanaKanjiConverter\lib\windows)"
swift test
```

The PATH entry is required because the engine module links llama.cpp; the test
runner cannot start without `llama.dll` / `ggml*.dll`.

Engine conversion regression tests require `build\x64\release\azookey-engine.dll`.
Build the DLL first, then run from the repository root:

```powershell
# 補正が出るべきケース + 誤検出しないべきケース
python scripts/tests/typo_conversion_test.py

# 正しく打てている日常文30件に補正候補が混入しないこと(予算12/60)
python scripts/tests/typo_clean_sweep_test.py
```
