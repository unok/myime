"""正しく打てている日常文にタイポ補正候補が混入しないことの回帰テスト。

実測で確認した混入例(修正済み): 「んよろしくお願いします」(先頭ん挿入)、
「ちょっと待ってくだしあ」(転置)、「的を開けてもいいですか」(まと置換)、
「中が好きました」(お削除)。原因は位置推定の誤発火と、長文総当たり経路の
改善バー欠如・生値比較の読み長非対称。モーラ正規化バー+マージンで抑止した。
"""

import ctypes
import json
import os
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD_DIR = ROOT / "build" / "x64" / "release"
DLL_PATH = BUILD_DIR / "azookey-engine.dll"

CLEAN_SENTENCES = [
    "きょうはいいてんきですね",
    "おはようございますみなさん",
    "ありがとうございました",
    "よろしくおねがいします",
    "おつかれさまでした",
    "すみませんおくれます",
    "あしたはあめがふりそうです",
    "でんしゃがおくれています",
    "かいぎをはじめましょう",
    "しりょうをおくります",
    "ごはんをたべにいきませんか",
    "きのうはたのしかったです",
    "ちょっとまってください",
    "いまむかっています",
    "もうすこしでつきます",
    "ほんとうにありがとう",
    "たんじょうびおめでとう",
    "しゅくだいがおわりません",
    "ねむくてしかたがない",
    "みずをのみたいです",
    "えきまであるいていきます",
    "にちようびにえいがをみにいく",
    "しごとがいそがしいです",
    "かぜをひいてしまいました",
    "はやくねたほうがいいですよ",
    "おなかがすきました",
    "あたらしいくつをかいました",
    "でんきをけしてください",
    "まどをあけてもいいですか",
    "こんしゅうまつはいえにいます",
]

SHORT_CLEAN_WORDS = [
    "きょう", "きのう", "かいしゃ", "せんせい", "かぞく",
    "りんご", "みかん", "じかん", "とうきょう", "べんきょう",
    "しけん", "けんこう", "つかう", "つくる", "わかる",
    "ごはん", "さとう", "おちゃ", "でんしゃ", "じてんしゃ",
]


def load_engine():
    if not DLL_PATH.exists():
        print(f"{DLL_PATH} が見つかりません。build-x64.bat を先に実行してください。")
        sys.exit(2)

    # add_dll_directory はハンドルを返し、GC で解放されると検索パスが外れて
    # 遅延ロード(ggml バックエンド等)が壊れうる。エンジンの生存期間中保持する
    global _dll_dir_handle
    _dll_dir_handle = os.add_dll_directory(str(BUILD_DIR))
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


def main():
    engine = load_engine()
    memory_path = tempfile.mkdtemp(prefix="azookey-typo-sweep-").encode("utf-8")

    if engine.Initialize(b"", memory_path) != 1:
        print("FAIL: Initialize failed")
        return 1

    try:
        engine.SetTypoCorrectionEnabled(True)
        failures = 0
        # 12=スペース変換、60=アイドル再サジェストの実運用予算
        for budget in (12, 60):
            engine.SetTypoCorrectionBudget(budget)
            for reading in CLEAN_SENTENCES:
                candidates = convert(engine, reading)
                typos = [c["text"] for c in candidates if c.get("typoCorrected") is True]
                if typos:
                    failures += 1
                    print(f"FAIL: b{budget} {reading} に補正候補が混入: {typos}")
            for reading in SHORT_CLEAN_WORDS:
                candidates = convert(engine, reading)
                typos = [c["text"] for c in candidates if c.get("typoCorrected") is True]
                if typos:
                    failures += 1
                    print(f"FAIL: b{budget} short {reading} に補正候補が混入: {typos}")

        if failures == 0:
            print(
                "PASS: typo clean sweep "
                f"({len(CLEAN_SENTENCES)}文 + {len(SHORT_CLEAN_WORDS)}短語) x 予算2種"
            )
            return 0
        return 1
    finally:
        engine.Shutdown()


if __name__ == "__main__":
    sys.exit(main())
