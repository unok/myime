import ctypes
import json
import os
import sys
import tempfile
from pathlib import Path


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

    os.add_dll_directory(str(BUILD_DIR))
    os.chdir(BUILD_DIR)

    engine = ctypes.CDLL(str(DLL_PATH))
    engine.Initialize.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    engine.Initialize.restype = ctypes.c_int32
    engine.Shutdown.argtypes = []
    engine.Shutdown.restype = None
    engine.ConvertText.argtypes = [ctypes.c_char_p, ctypes.c_int32]
    # c_char_p にすると ctypes が bytes へ即時変換してポインタを失い、
    # FreeString で解放できなくなる。c_void_p で受けて明示的に解放する
    engine.ConvertText.restype = ctypes.c_void_p
    engine.FreeString.argtypes = [ctypes.c_void_p]
    engine.FreeString.restype = None
    engine.SetTypoCorrectionEnabled.argtypes = [ctypes.c_bool]
    engine.SetTypoCorrectionEnabled.restype = None
    engine.SetTypoCorrectionBudget.argtypes = [ctypes.c_int32]
    engine.SetTypoCorrectionBudget.restype = None
    return engine


def convert(engine, reading):
    ptr = engine.ConvertText(reading.encode("utf-8"), 0)
    if not ptr:
        raise RuntimeError(f"ConvertText returned null for {reading}")
    try:
        return json.loads(ctypes.string_at(ptr).decode("utf-8"))
    finally:
        engine.FreeString(ptr)


def typo_candidates(candidates):
    return [candidate for candidate in candidates if candidate.get("typoCorrected") is True]


def has_typo_candidate(candidates, expected_texts):
    expected = set(expected_texts)
    return any(candidate.get("text") in expected for candidate in typo_candidates(candidates))


def main():
    engine = load_engine()
    memory_path = tempfile.mkdtemp(prefix="azookey-typo-test-").encode("utf-8")

    # Keep dictionaryPath empty. The Swift engine uses the bundled default dictionary
    # only when this argument is empty; passing a non-empty path selects a custom
    # dictionary and can accidentally create a dictionary-less engine.
    if engine.Initialize(b"", memory_path) != 1:
        print("FAIL: Initialize failed")
        return 1

    try:
        engine.SetTypoCorrectionEnabled(True)
        engine.SetTypoCorrectionBudget(12)

        checks = []
        for reading, expected in [
            ("がこう", ["学校"]),
            ("こにちは", ["こんにちは"]),
            ("ありがつお", ["ありがとう"]),
            ("ほにゃ", ["本屋"]),
            ("きょうお", ["京都"]),
            ("でs", ["です"]),
            ("ありがとうございまs", ["有難うございます", "ありがとうございます"]),
            ("しゃsひん", ["写真"]),
        ]:
            candidates = convert(engine, reading)
            checks.append(
                has_typo_candidate(candidates, expected)
                or fail(f"{reading} should include typo-corrected {expected}; got {candidates}")
            )

        for reading in ["こんにちは", "ありがとう", "がっこう", "にほんご"]:
            candidates = convert(engine, reading)
            typo_count = len(typo_candidates(candidates))
            checks.append(
                typo_count == 0
                or fail(f"{reading} should have zero typo-corrected candidates; got {candidates}")
            )

        if all(checks):
            print("PASS: typo conversion regression tests")
            return 0
        return 1
    finally:
        engine.Shutdown()


if __name__ == "__main__":
    sys.exit(main())
