"""Benchmark the cost of pushing a complete dynamic user dictionary.

This measures how SetUserDictionary push cost grows with dictionary size, to
help decide whether incremental/diff synchronization is needed instead of a
full re-push on every engine initialization.

Usage example:
    python scripts/bench/user_dictionary_push_bench.py --sizes 100,1000,10000

Rule of thumb: if set_ms at 10,000 entries is under 100 ms, diff sync is likely
unnecessary. If set_ms grows much worse than linearly, diff sync is worth
pursuing.
"""

import argparse
import ctypes
import json
import os
import random
import statistics
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DLL_DIR = Path("build") / "x64" / "release"
DLL_NAME = "azookey-engine.dll"
FIXED_SEED = 0x55A2002

HIRAGANA = tuple(
    "あいうえおかきくけこさしすせそたちつてとなにぬねの"
    "はひふへほまみむめもやゆよらりるれろわをん"
)
KANJI = tuple("日月火水木金土山川田中本語空海花森谷島村高新大小")
KATAKANA = tuple("アイウエオカキクケコサシスセソタチツテトナニヌネノ")
POS_FEATURES = (
    "名詞,一般,*,*,*,*",
    "名詞,固有名詞,人名,姓,*,*",
    "名詞,固有名詞,地域,一般,*,*",
    "動詞,自立,*,*,五段・カ行イ音便,連用形",
)
POS_WEIGHTS = (70, 10, 10, 10)

_dll_dir_handle = None


def parse_sizes(value):
    try:
        sizes = [int(item.strip()) for item in value.split(",")]
    except ValueError as exc:
        raise argparse.ArgumentTypeError("sizes must be comma-separated integers") from exc
    if not sizes or any(size <= 0 for size in sizes):
        raise argparse.ArgumentTypeError("sizes must contain positive integers")
    return sizes


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sizes",
        type=parse_sizes,
        default=parse_sizes("100,1000,10000,50000"),
        help="comma-separated dictionary sizes (default: 100,1000,10000,50000)",
    )
    parser.add_argument(
        "--repeat",
        type=int,
        default=3,
        help="trials per size (default: 3)",
    )
    parser.add_argument(
        "--dll",
        type=Path,
        default=DEFAULT_DLL_DIR,
        help="directory containing azookey-engine.dll (default: build/x64/release)",
    )
    args = parser.parse_args()
    if args.repeat <= 0:
        parser.error("--repeat must be positive")
    return args


def resolve_dll_dir(value):
    return value.resolve() if value.is_absolute() else (ROOT / value).resolve()


def load_engine(dll_dir):
    dll_path = dll_dir / DLL_NAME
    if not dll_path.exists():
        print(f"ERROR: DLL not found: {dll_path}", file=sys.stderr)
        return None

    # Keep the handle alive for the engine lifetime so delayed dependency loads
    # continue to search this directory. This mirrors typo_conversion_test.py.
    global _dll_dir_handle
    _dll_dir_handle = os.add_dll_directory(str(dll_dir))
    os.chdir(dll_dir)

    engine = ctypes.CDLL(str(dll_path))
    engine.Initialize.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    engine.Initialize.restype = ctypes.c_int32
    engine.Shutdown.argtypes = []
    engine.Shutdown.restype = None
    engine.SetUserDictionary.argtypes = [ctypes.c_char_p]
    engine.SetUserDictionary.restype = ctypes.c_int32
    engine.SetZenzaiEnabled.argtypes = [ctypes.c_bool]
    engine.SetZenzaiEnabled.restype = None
    engine.ConvertText.argtypes = [ctypes.c_char_p, ctypes.c_int32]
    engine.ConvertText.restype = ctypes.c_void_p
    engine.FreeString.argtypes = [ctypes.c_void_p]
    engine.FreeString.restype = None
    return engine


def random_reading(rng, excluded):
    while True:
        reading = "".join(rng.choice(HIRAGANA) for _ in range(rng.randint(2, 6)))
        if reading not in excluded:
            return reading


def random_word(rng):
    katakana = "".join(rng.choice(KATAKANA) for _ in range(rng.randint(1, 3)))
    return rng.choice(KANJI) + katakana + rng.choice(KANJI)


def make_entries(size, trial, previously_used_readings):
    # A fixed, size/trial-derived seed makes every requested trial reproducible.
    rng = random.Random(FIXED_SEED + size * 1_000_003 + trial)
    entries = []
    current_readings = set()
    excluded = set(previously_used_readings)
    for _ in range(size):
        reading = random_reading(rng, excluded)
        excluded.add(reading)
        current_readings.add(reading)
        entries.append(
            {
                "reading": reading,
                "word": random_word(rng),
                "pos": rng.choices(POS_FEATURES, weights=POS_WEIGHTS, k=1)[0],
            }
        )

    miss_reading = random_reading(rng, excluded)
    previously_used_readings.update(current_readings)
    previously_used_readings.add(miss_reading)
    return entries, entries[0]["reading"], miss_reading


def build_payload(entries):
    start = time.perf_counter_ns()
    payload = json.dumps(
        entries, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    return payload, elapsed_ms(start)


def elapsed_ms(start_ns):
    return (time.perf_counter_ns() - start_ns) / 1_000_000.0


def convert_once(engine, reading):
    start = time.perf_counter_ns()
    ptr = engine.ConvertText(reading.encode("utf-8"), 0)
    duration_ms = elapsed_ms(start)
    if not ptr:
        raise RuntimeError("ConvertText returned null")
    try:
        # Materialize the result while the DLL-allocated buffer is still valid.
        ctypes.string_at(ptr)
    finally:
        # ConvertText uses _strdup; free it through the DLL's matching allocator.
        engine.FreeString(ptr)
    return duration_ms


def print_table(rows, baseline_rows):
    headers = ("size", "build_ms", "set_ms", "convert_hit_ms", "convert_miss_ms")
    formatted = [
        (
            str(row[0]),
            f"{row[1]:.3f}",
            f"{row[2]:.3f}",
            f"{row[3]:.3f}",
            f"{row[4]:.3f}",
        )
        for row in rows
    ]
    widths = [
        max(len(headers[index]), *(len(row[index]) for row in formatted))
        for index in range(len(headers))
    ]
    print("  ".join(header.rjust(widths[index]) for index, header in enumerate(headers)))
    print("  ".join("-" * width for width in widths))
    for row in formatted:
        print("  ".join(value.rjust(widths[index]) for index, value in enumerate(row)))

    print()
    print("Reference: median conversion before the trial payload was pushed")
    baseline_header = ("size", "baseline_before_set_ms")
    baseline_formatted = [(str(size), f"{duration:.3f}") for size, duration in baseline_rows]
    baseline_widths = [
        max(
            len(baseline_header[index]),
            *(len(row[index]) for row in baseline_formatted),
        )
        for index in range(len(baseline_header))
    ]
    print(
        "  ".join(
            header.rjust(baseline_widths[index])
            for index, header in enumerate(baseline_header)
        )
    )
    print("  ".join("-" * width for width in baseline_widths))
    for row in baseline_formatted:
        print(
            "  ".join(
                value.rjust(baseline_widths[index])
                for index, value in enumerate(row)
            )
        )


def main():
    args = parse_args()
    engine = load_engine(resolve_dll_dir(args.dll))
    if engine is None:
        return 2

    rows = []
    baseline_rows = []
    used_readings = set()

    with tempfile.TemporaryDirectory(prefix="azookey-user-dict-bench-") as memory_path:
        # As in typo_conversion_test.py, an empty dictionary path selects the
        # bundled dictionary and a temporary memory path isolates learning data.
        if engine.Initialize(b"", memory_path.encode("utf-8")) != 1:
            print("ERROR: Initialize failed", file=sys.stderr)
            return 2

        try:
            # typo_conversion_test.py has no environment or registry override for
            # Zenzai. EngineConfig defaults it to false; make that state explicit.
            engine.SetZenzaiEnabled(False)

            for size in args.sizes:
                build_times = []
                set_times = []
                hit_times = []
                miss_times = []
                baseline_times = []

                for trial in range(1, args.repeat + 1):
                    entries, hit_reading, miss_reading = make_entries(
                        size, trial, used_readings
                    )
                    payload, build_ms = build_payload(entries)
                    build_times.append(build_ms)

                    # Trial payloads use disjoint readings, so this measures the
                    # hit reading before the dynamic dictionary contains it.
                    baseline_times.append(convert_once(engine, hit_reading))

                    start = time.perf_counter_ns()
                    result = engine.SetUserDictionary(payload)
                    set_times.append(elapsed_ms(start))
                    if result != 1:
                        print(
                            f"ERROR: SetUserDictionary failed for size={size}, "
                            f"iteration={trial}",
                            file=sys.stderr,
                        )
                        return 1

                    # Repeated calls are assumed to replace rather than append:
                    # the Swift C export documents complete replacement, and the
                    # Mozc bridge rebuilds a full JSON snapshot for every push.
                    hit_times.append(convert_once(engine, hit_reading))
                    miss_times.append(convert_once(engine, miss_reading))

                rows.append(
                    (
                        size,
                        statistics.median(build_times),
                        statistics.median(set_times),
                        statistics.median(hit_times),
                        statistics.median(miss_times),
                    )
                )
                baseline_rows.append((size, statistics.median(baseline_times)))
        except (OSError, RuntimeError) as exc:
            print(f"ERROR: benchmark failed: {exc}", file=sys.stderr)
            return 2
        finally:
            engine.Shutdown()

    print_table(rows, baseline_rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
