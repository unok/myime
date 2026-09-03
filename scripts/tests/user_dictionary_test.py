import ctypes
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path


sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parents[2]
BUILD_DIR = ROOT / "build" / "x64" / "release"
DLL_PATH = BUILD_DIR / "azookey-engine.dll"


def fail(message):
    print(f"FAIL: {message}")
    return False


def load_engine():
    if not DLL_PATH.exists():
        print(f"{DLL_PATH} が見つかりません。build-x64.bat を先に実行してください。")
        sys.exit(2)

    global _dll_dir_handle
    _dll_dir_handle = os.add_dll_directory(str(BUILD_DIR))
    os.chdir(BUILD_DIR)

    engine = ctypes.CDLL(str(DLL_PATH))
    engine.Initialize.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    engine.Initialize.restype = ctypes.c_int32
    engine.Shutdown.argtypes = []
    engine.Shutdown.restype = None
    engine.SetUserDictionary.argtypes = [ctypes.c_char_p]
    engine.SetUserDictionary.restype = ctypes.c_int32
    engine.ConvertText.argtypes = [ctypes.c_char_p, ctypes.c_int32]
    engine.ConvertText.restype = ctypes.c_void_p
    engine.FreeString.argtypes = [ctypes.c_void_p]
    engine.FreeString.restype = None
    return engine


def convert(engine, reading):
    ptr = engine.ConvertText(reading.encode("utf-8"), 0)
    if not ptr:
        raise RuntimeError(f"ConvertText returned null for {reading}")
    try:
        return json.loads(ctypes.string_at(ptr).decode("utf-8"))
    finally:
        engine.FreeString(ptr)


def contains_text(candidates, expected):
    return any(candidate.get("text") == expected for candidate in candidates)


def main():
    engine = load_engine()
    memory_dir = tempfile.mkdtemp(prefix="azookey-user-dictionary-test-")
    memory_path = memory_dir.encode("utf-8")

    if engine.Initialize(b"", memory_path) != 1:
        print("FAIL: Initialize failed")
        return 1

    try:
        entries = [
            {
                "reading": "ほげる",
                "word": "捕華る",
                "pos": "動詞,自立,*,*,五段・カ行イ音便,基本形",
            },
            {
                "reading": "ほげり",
                "word": "捕華り",
                "pos": "動詞,自立,*,*,五段・カ行イ音便,連用形",
            },
            {
                "reading": "ほげっ",
                "word": "捕華っ",
                "pos": "動詞,自立,*,*,五段・カ行イ音便,連用タ接続",
            },
            {
                "reading": "ぬめきがわ",
                "word": "滑奇河",
                "pos": "名詞,固有名詞,人名,姓,*,*",
            },
            {
                "reading": "こでっくすぞうご",
                "word": "符典造語",
                "pos": "noun",
            },
        ]
        payload = json.dumps(entries, ensure_ascii=False).encode("utf-8")
        if engine.SetUserDictionary(payload) != 1:
            print("FAIL: SetUserDictionary failed")
            return 1

        checks = []
        for reading, expected in [
            ("ほげる", "捕華る"),
            ("ほげります", "捕華ります"),
            ("ほげった", "捕華った"),
            ("ぬめきがわ", "滑奇河"),
            ("こでっくすぞうご", "符典造語"),
        ]:
            candidates = convert(engine, reading)
            checks.append(
                contains_text(candidates, expected)
                or fail(f"{reading} should include {expected}; got {candidates}")
            )

        if all(checks):
            print("PASS: user dictionary feature and compatibility tests")
            return 0
        return 1
    finally:
        engine.Shutdown()
        shutil.rmtree(memory_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
