#!/usr/bin/env python3
"""Collect typo-correction scores and replay the hand-tuned thresholds.

This calibration harness loads azookey-engine.dll, disables Zenzai, enables
AZOOKEY_TYPO_DEBUG, and converts every case in scripts/tests/typo_cases.json.
It captures the DLL's C stderr with os.dup2 (replacing sys.stderr is not
enough), prints ASCII case/sweep/category tables, and can save all raw and
parsed observations with ``--json``.

Typical use::

    python scripts/bench/typo_calibration.py
    python scripts/bench/typo_calibration.py --budget 60 --json typo-raw.json
    python scripts/bench/typo_calibration.py --budget 60 --no-nonterminal-filter
    python scripts/bench/typo_calibration.py --sweep=-3.0:-1.0:0.1 \
        --sweep-bar=2.0:6.0:0.5 \
        --sweep-solid=-5.0:-3.0:0.25 --sweep-improve=-0.5:1.0:0.1 \
        --sweep-min-length=1:4:1

Replay summary: a short-path candidate with a solid one-word literal must
strictly exceed that literal by the configured improvement (currently +2.0);
fragmented inputs retain the signed margin (currently -1.8), and inputs under
the configured minimum length (currently 3) are rejected.  These checks follow
the best-value-minus-4 cutoff.  Long-path candidates must exceed the literal
whole-sentence value normalized to the corrected reading length plus the
improvement bar (currently +4.0), as well as the strict -6 per-character
absolute bar.  Source function references accompany the copied formulas.
By default replay applies the nonterminal-conjugation filter; pass
``--no-nonterminal-filter`` to include candidates logged with
``decision=nonterminal`` and compare the counterfactual result.

The long-bar replay is necessarily limited to the six ``top=`` candidates
which the DLL logs for each attempted reading.  The JSON output retains those
raw observations so a calibration result can be audited against the DLL log.
"""

import argparse
import ctypes
import json
import math
import os
import re
import statistics
import sys
import tempfile
import unicodedata
from decimal import Decimal
from pathlib import Path


sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DLL = ROOT / "build" / "x64" / "release"
DEFAULT_CASES = ROOT / "scripts" / "tests" / "typo_cases.json"
CURRENT_SHORT_MARGIN = -1.8
CURRENT_LONG_BAR = 4.0
CURRENT_SOLID_LITERAL_PER_MORA = -5.0
CURRENT_SOLID_LITERAL_IMPROVEMENT = 2.0
CURRENT_MINIMUM_INPUT_LENGTH = 3
VALUE_CUTOFF_WIDTH = 4.0
ABSOLUTE_VALUE_PER_CHAR = -6.0
MAX_TYPO_CANDIDATES = 3

READING_LINE = re.compile(
    r"^\[typo\] key=(.*?) reading=(.*?) bar=(.*?) top=(.*)$"
)
SELECTION_LINE = re.compile(
    r"^\[typo\] key=(.*?) literalBestPerMora=(\S+) literalTop=(.*?) ranked=(.*)$"
)
SELECTION_GATE_LINE = re.compile(
    r"^\[typo\] key=(.*?) literalWholeBestPerMora=(\S+) "
    r"literalWholeBestText=(.*?) gate=(solid|fragment|too_short)$"
)
CANDIDATE_LINE = re.compile(
    r"^\[typo\] key=(.*?) reading=(.*?) candidate=(.*?) value=(\S+) "
    r"lastCid=(\S+) form=(.*?) decision=(eligible|nonterminal)$"
)


def parse_args():
    # argparse mistakes a colon-delimited negative sweep for another option;
    # accept both ``--sweep=-3:...`` and the requested ``--sweep -3:...`` form.
    argv = list(sys.argv[1:])
    for option in ("--sweep", "--sweep-bar", "--sweep-solid", "--sweep-improve"):
        if option in argv:
            index = argv.index(option)
            if index + 1 < len(argv) and argv[index + 1].startswith("-"):
                argv[index : index + 2] = [f"{option}={argv[index + 1]}"]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dll",
        type=Path,
        default=DEFAULT_DLL,
        help="DLL directory or azookey-engine.dll path (default: build/x64/release)",
    )
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--budget", type=int, default=12)
    parser.add_argument("--sweep", default="-3.0:-1.0:0.1")
    parser.add_argument("--sweep-bar", default="2.0:6.0:0.5")
    parser.add_argument("--sweep-solid", default="-5.0:-3.0:0.25")
    parser.add_argument("--sweep-improve", default="-0.5:1.0:0.1")
    parser.add_argument("--sweep-min-length", default="1:4:1")
    parser.add_argument(
        "--no-nonterminal-filter",
        action="store_true",
        help="replay logged candidates as if the nonterminal-conjugation filter were disabled",
    )
    parser.add_argument("--json", type=Path, dest="json_output")
    return parser.parse_args(argv)


def resolve_from_root(path):
    return path.resolve() if path.is_absolute() else (ROOT / path).resolve()


def decimal_sweep(spec):
    try:
        start, stop, step = (Decimal(value) for value in spec.split(":"))
    except (ValueError, ArithmeticError) as exc:
        raise argparse.ArgumentTypeError(
            f"invalid sweep {spec!r}; expected START:STOP:STEP"
        ) from exc
    if step == 0 or (stop - start) * step < 0:
        raise argparse.ArgumentTypeError(f"invalid sweep direction: {spec!r}")
    values = []
    value = start
    compare = (lambda item: item <= stop) if step > 0 else (lambda item: item >= stop)
    while compare(value):
        values.append(value)
        value += step
    return values


def parse_number(value):
    if value == "nil":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def parse_top_items(payload):
    items = []
    for token in payload.split():
        parts = token.rsplit("/", 5)
        if len(parts) not in (3, 6):
            continue
        if len(parts) == 6:
            text, ruby_count, value, last_cid, form, terminality = parts
        else:
            text, ruby_count, value = parts
            last_cid, form, terminality = "nil", "nil", "terminal"
        try:
            items.append(
                {
                    "text": text,
                    "ruby_count": int(ruby_count),
                    "value": float(value),
                    "last_cid": None if last_cid == "nil" else int(last_cid),
                    "conjugation_form": None if form == "nil" else form,
                    "nonterminal": terminality == "nonterminal",
                }
            )
        except ValueError:
            continue
    return items


def parse_ranked_items(payload):
    items = []
    for token in payload.split():
        parts = token.rsplit("/", 4)
        if len(parts) not in (3, 5):
            continue
        if len(parts) == 5:
            text, reading, value, last_cid, form = parts
        else:
            text, reading, value = parts
            last_cid, form = "nil", "nil"
        try:
            items.append(
                {
                    "text": text,
                    "corrected_reading": reading,
                    "value": float(value),
                    "last_cid": None if last_cid == "nil" else int(last_cid),
                    "conjugation_form": None if form == "nil" else form,
                }
            )
        except ValueError:
            continue
    return items


def parse_debug_log(raw_log, expected_key):
    attempts = []
    candidates = []
    selection = None
    selection_gate = None
    for line in raw_log.splitlines():
        match = READING_LINE.match(line)
        if match and match.group(1) == expected_key:
            attempts.append(
                {
                    "reading": match.group(2),
                    "bar": parse_number(match.group(3)),
                    "top": parse_top_items(match.group(4)),
                    "raw": line,
                }
            )
            continue
        match = SELECTION_LINE.match(line)
        if match and match.group(1) == expected_key:
            selection = {
                "literal_best_per_mora": parse_number(match.group(2)),
                "literal_top": parse_top_items(match.group(3)),
                "ranked": parse_ranked_items(match.group(4)),
                "raw": line,
            }
            continue
        match = CANDIDATE_LINE.match(line)
        if match and match.group(1) == expected_key:
            candidates.append(
                {
                    "reading": match.group(2),
                    "text": match.group(3),
                    "value": float(match.group(4)),
                    "last_cid": None if match.group(5) == "nil" else int(match.group(5)),
                    "conjugation_form": None if match.group(6) == "nil" else match.group(6),
                    "decision": match.group(7),
                    "raw": line,
                }
            )
            continue
        match = SELECTION_GATE_LINE.match(line)
        if match and match.group(1) == expected_key:
            selection_gate = {
                "literal_whole_best_per_mora": parse_number(match.group(2)),
                "literal_whole_best_text": None if match.group(3) == "nil" else match.group(3),
                "gate": match.group(4),
                "raw": line,
            }
    return {
        "attempts": attempts,
        "candidates": candidates,
        "selection": selection,
        "selection_gate": selection_gate,
    }


def load_engine(dll_argument):
    dll_argument = resolve_from_root(dll_argument)
    dll_path = (
        dll_argument / "azookey-engine.dll" if dll_argument.is_dir() else dll_argument
    )
    if not dll_path.exists():
        raise FileNotFoundError(f"{dll_path} not found; run build-x64.bat first")

    # TypoCorrectionPass.swift initializes typoDebugEnabled when the DLL loads.
    os.environ["AZOOKEY_TYPO_DEBUG"] = "1"
    global _dll_dir_handle
    _dll_dir_handle = os.add_dll_directory(str(dll_path.parent))
    os.chdir(dll_path.parent)
    engine = ctypes.CDLL(str(dll_path))
    engine.Initialize.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    engine.Initialize.restype = ctypes.c_int32
    engine.Shutdown.argtypes = []
    engine.Shutdown.restype = None
    engine.ConvertText.argtypes = [ctypes.c_char_p, ctypes.c_int32]
    # Keep the allocation pointer until FreeString, matching typo_conversion_test.py.
    engine.ConvertText.restype = ctypes.c_void_p
    engine.FreeString.argtypes = [ctypes.c_void_p]
    engine.FreeString.restype = None
    engine.SetTypoCorrectionEnabled.argtypes = [ctypes.c_bool]
    engine.SetTypoCorrectionEnabled.restype = None
    engine.SetTypoCorrectionBudget.argtypes = [ctypes.c_int32]
    engine.SetTypoCorrectionBudget.restype = None
    engine.SetZenzaiEnabled.argtypes = [ctypes.c_bool]
    engine.SetZenzaiEnabled.restype = None
    return engine, dll_path


def flush_c_stderr():
    sys.stderr.flush()
    try:
        ctypes.CDLL("ucrtbase.dll").fflush(None)
    except (OSError, AttributeError):
        pass


def convert_with_debug(engine, reading):
    """Convert once while fd 2 points at a temporary file."""
    saved_stderr = os.dup(2)
    try:
        with tempfile.TemporaryFile(mode="w+b") as capture:
            flush_c_stderr()
            os.dup2(capture.fileno(), 2)
            try:
                pointer = engine.ConvertText(reading.encode("utf-8"), 0)
                if not pointer:
                    raise RuntimeError(f"ConvertText returned null for {reading}")
                try:
                    result = json.loads(ctypes.string_at(pointer).decode("utf-8"))
                finally:
                    engine.FreeString(pointer)
                flush_c_stderr()
            finally:
                os.dup2(saved_stderr, 2)
            capture.seek(0)
            raw_log = capture.read().decode("utf-8", errors="replace")
    finally:
        os.close(saved_stderr)
    return result, raw_log


def fold_hiragana(text):
    folded = []
    for char in text:
        codepoint = ord(char)
        folded.append(chr(codepoint - 0x60) if 0x30A1 <= codepoint <= 0x30F6 else char)
    return "".join(folded)


def is_script_variant(text, reading):
    return text != reading and fold_hiragana(text) == reading


def contains_ascii_like_noise(text):
    return any(
        "0" <= char <= "9"
        or "A" <= char <= "Z"
        or "a" <= char <= "z"
        or "０" <= char <= "９"
        or "Ａ" <= char <= "Ｚ"
        or "ａ" <= char <= "ｚ"
        for char in text
    )


def has_alphabet(text):
    return any(
        "A" <= char <= "Z"
        or "a" <= char <= "z"
        or "Ａ" <= char <= "Ｚ"
        or "ａ" <= char <= "ｚ"
        for char in text
    )


def actual_typo_candidates(result):
    return [candidate for candidate in result if candidate.get("typoCorrected") is True]


def existing_texts(observation):
    texts = {
        candidate.get("text")
        for candidate in observation["result"]
        if candidate.get("typoCorrected") is not True and candidate.get("text") is not None
    }
    selection = observation["debug"].get("selection")
    if selection:
        texts.update(item["text"] for item in selection["literal_top"])
    return texts


def best_attempt_candidate(observation, attempt, bar_margin, nonterminal_filter=True):
    reading = attempt["reading"]
    alphabet_path = has_alphabet(observation["input"])
    candidates = []
    for candidate in attempt["top"]:
        # Mirrors makeTypoCandidates' eligible-candidate filters.
        if candidate["ruby_count"] != len(reading):
            continue
        if candidate["text"] in existing_texts(observation):
            continue
        if contains_ascii_like_noise(candidate["text"]):
            continue
        if is_script_variant(candidate["text"], reading):
            continue
        if nonterminal_filter and not alphabet_path and candidate.get("nonterminal", False):
            continue
        if not alphabet_path and candidate["text"] == reading and candidate["value"] <= -14:
            continue
        # Strict absolute bar from makeTypoCandidates' candidate filter.
        if not candidate["value"] > ABSOLUTE_VALUE_PER_CHAR * len(reading):
            continue
        if bar_margin is not None:
            whole_per_mora = observation.get("literal_whole_per_mora")
            # A nil best whole-sentence candidate produces bar=nil in
            # makeTypoCandidates, so the improvement comparison is not applied.
            if whole_per_mora is not None:
                # Mirrors makeTypoCandidates' normalized improvement bar.
                improvement_bar = whole_per_mora * len(reading) + bar_margin
                if not candidate["value"] > improvement_bar:
                    continue
        candidates.append(candidate)
    if not candidates:
        return None
    if alphabet_path:
        converted = [item for item in candidates if item["text"] != reading]
        if converted:
            candidates = converted
    best = max(candidates, key=lambda item: item["value"])
    return {
        "text": best["text"],
        "corrected_reading": reading,
        "value": best["value"],
        "last_cid": best.get("last_cid"),
        "conjugation_form": best.get("conjugation_form"),
    }


def candidates_from_events(observation, nonterminal_filter):
    """Recover each reading's best pre-selection candidate, including logged rejects."""
    by_reading = {}
    for candidate in observation["debug"].get("candidates", []):
        if nonterminal_filter and candidate["decision"] == "nonterminal":
            continue
        reading = candidate["reading"]
        current = by_reading.get(reading)
        if current is None or candidate["value"] > current["value"]:
            by_reading[reading] = {
                "text": candidate["text"],
                "corrected_reading": reading,
                "value": candidate["value"],
                "last_cid": candidate["last_cid"],
                "conjugation_form": candidate["conjugation_form"],
            }
    return list(by_reading.values())


def select_by_short_margin(
    observation,
    candidates,
    margin,
    solid_literal_per_mora=CURRENT_SOLID_LITERAL_PER_MORA,
    solid_literal_improvement=CURRENT_SOLID_LITERAL_IMPROVEMENT,
    minimum_input_length=CURRENT_MINIMUM_INPUT_LENGTH,
):
    """Replay TypoCorrectionPass.selectTypoCandidates."""
    literal_best = observation.get("literal_best_per_mora")
    if literal_best is None:
        return []
    # The selectTypoCandidates length gate is replayed from the logged first-pass
    # observation;
    # changing a sweep value therefore never requires another DLL conversion.
    if observation["length"] <= 8 and observation["length"] < minimum_input_length:
        return []
    literal_whole_best = observation.get("literal_whole_best_per_mora")
    solid_gate = (
        observation["length"] <= 8
        and literal_whole_best is not None
        and literal_whole_best >= solid_literal_per_mora
    )
    ranked = sorted(candidates, key=lambda item: item["value"], reverse=True)
    if not ranked:
        return []
    value_cutoff = ranked[0]["value"] - VALUE_CUTOFF_WIDTH
    seen = set(existing_texts(observation))
    selected = []
    for candidate in ranked:
        if candidate["value"] < value_cutoff:
            break
        per_mora = candidate["value"] / max(1, len(candidate["corrected_reading"]))
        # The selectTypoCandidates solid branch requires a strict improvement;
        # fragmented inputs retain the inclusive signed margin.
        if solid_gate:
            if not per_mora > literal_whole_best + solid_literal_improvement:
                continue
        elif per_mora < literal_best + margin:
            continue
        if candidate["text"] in seen:
            continue
        seen.add(candidate["text"])
        selected.append(candidate)
        if len(selected) == MAX_TYPO_CANDIDATES:
            break
    return selected


def replay(
    observation,
    short_margin=CURRENT_SHORT_MARGIN,
    long_bar=CURRENT_LONG_BAR,
    solid_literal_per_mora=CURRENT_SOLID_LITERAL_PER_MORA,
    solid_literal_improvement=CURRENT_SOLID_LITERAL_IMPROVEMENT,
    minimum_input_length=CURRENT_MINIMUM_INPUT_LENGTH,
    nonterminal_filter=True,
):
    if has_alphabet(observation["input"]):
        # makeTypoCandidates' alphabet-leftover branch bypasses selectTypoCandidates.
        candidates = [
            candidate
            for attempt in observation["debug"]["attempts"]
            for candidate in [best_attempt_candidate(
                observation, attempt, None, nonterminal_filter
            )]
            if candidate is not None
        ]
        return sorted(candidates, key=lambda item: item["value"], reverse=True)[
            :MAX_TYPO_CANDIDATES
        ]

    if observation["path"] == "long":
        if (
            not nonterminal_filter
            and long_bar == CURRENT_LONG_BAR
            and observation["debug"].get("candidates")
        ):
            candidates = candidates_from_events(observation, nonterminal_filter=False)
        else:
            candidates = [
                candidate
                for attempt in observation["debug"]["attempts"]
                for candidate in [best_attempt_candidate(
                    observation, attempt, long_bar, nonterminal_filter
                )]
                if candidate is not None
            ]
    else:
        if not nonterminal_filter and observation["debug"].get("candidates"):
            candidates = candidates_from_events(observation, nonterminal_filter=False)
        else:
            selection = observation["debug"].get("selection")
            candidates = selection["ranked"] if selection else []
    return select_by_short_margin(
        observation,
        candidates,
        short_margin,
        solid_literal_per_mora,
        solid_literal_improvement,
        minimum_input_length,
    )


def enrich_observation(case, kind, result, raw_log):
    reading = case["input"]
    debug = parse_debug_log(raw_log, reading)
    selection = debug.get("selection")
    selection_gate = debug.get("selection_gate")
    literal_best = selection.get("literal_best_per_mora") if selection else None
    actual = actual_typo_candidates(result)
    accepted_pairs = {
        (candidate.get("text"), candidate.get("correctedReading")) for candidate in actual
    }
    for attempt in debug["attempts"]:
        for candidate in attempt["top"]:
            candidate["corrected_reading"] = attempt["reading"]
            candidate["per_mora"] = candidate["value"] / max(1, len(attempt["reading"]))
            candidate["bar"] = attempt["bar"]
            candidate["accepted"] = (candidate["text"], attempt["reading"]) in accepted_pairs

    candidate_observations = []
    if selection:
        ranked_candidates = selection["ranked"]
    else:
        ranked_candidates = []
        # makeTypoCandidates' alphabet-leftover return skips the selection log.
        # Preserve the best filtered item for each attempted reading instead.
        shell = {
            "input": reading,
            "result": result,
            "debug": debug,
            "literal_whole_per_mora": None,
        }
        for attempt in debug["attempts"]:
            candidate = best_attempt_candidate(shell, attempt, None)
            if candidate:
                ranked_candidates.append(candidate)
    attempt_bars = {attempt["reading"]: attempt["bar"] for attempt in debug["attempts"]}
    for candidate in ranked_candidates:
        corrected_reading = candidate["corrected_reading"]
        candidate_observations.append(
            {
                "text": candidate["text"],
                "value": candidate["value"],
                "correctedReading": corrected_reading,
                "perMora": candidate["value"] / max(1, len(corrected_reading)),
                "bar": attempt_bars.get(corrected_reading),
                "accepted": (candidate["text"], corrected_reading) in accepted_pairs,
            }
        )

    observation = {
        "input": reading,
        "kind": kind,
        "category": case.get("category", "clean_sentences"),
        "expect": case.get("expect"),
        "expect_absent": case.get("expect_absent", []),
        "tentative": bool(case.get("tentative", False)),
        "note": case.get("note", ""),
        "length": len(reading),
        "path": "short" if len(reading) <= 8 else "long",
        "literal_best_per_mora": literal_best,
        "literal_whole_per_mora": None,
        "literal_whole_best_per_mora": (
            selection_gate.get("literal_whole_best_per_mora") if selection_gate else None
        ),
        "literal_whole_best_text": (
            selection_gate.get("literal_whole_best_text") if selection_gate else None
        ),
        "result": result,
        "actual_typo_candidates": actual,
        "candidate_observations": candidate_observations,
        "nonterminal_candidates": [
            candidate for candidate in debug.get("candidates", [])
            if candidate["decision"] == "nonterminal"
        ],
        "raw_stderr": raw_log,
        "debug": debug,
    }
    inferred = []
    for attempt in debug["attempts"]:
        if attempt["bar"] is not None and len(attempt["reading"]) > 0:
            inferred.append(
                (attempt["bar"] - CURRENT_LONG_BAR) / len(attempt["reading"])
            )
    if inferred:
        observation["literal_whole_per_mora"] = statistics.median(inferred)
    return observation


def best_candidate(observation, nonterminal_filter=True):
    selection = observation["debug"].get("selection")
    if not nonterminal_filter and observation["debug"].get("candidates"):
        values = candidates_from_events(observation, nonterminal_filter=False)
    else:
        values = list(selection["ranked"]) if selection else []
    for attempt in observation["debug"]["attempts"]:
        # Keep the best score behind the current long bar visible in the case
        # and category tables; it is exactly what a lower bar may admit.
        candidate = best_attempt_candidate(
            observation, attempt, None, nonterminal_filter
        )
        if candidate:
            values.append(candidate)
    return max(values, key=lambda item: item["value"]) if values else None


def per_mora_diff(observation, candidate):
    if not candidate or observation["literal_best_per_mora"] is None:
        return None
    candidate_per_mora = candidate["value"] / max(
        1, len(candidate["corrected_reading"])
    )
    return candidate_per_mora - observation["literal_best_per_mora"]


def display_width(value):
    return sum(2 if unicodedata.east_asian_width(char) in "WFA" else 1 for char in value)


def ascii_table(headers, rows):
    rendered = [[str(value) for value in row] for row in rows]
    widths = [display_width(str(header)) for header in headers]
    for row in rendered:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], display_width(value))

    def padded(value, width):
        return value + " " * (width - display_width(value))

    separator = "+" + "+".join("-" * (width + 2) for width in widths) + "+"
    output = [separator]
    output.append(
        "| " + " | ".join(padded(str(value), widths[index]) for index, value in enumerate(headers)) + " |"
    )
    output.append(separator)
    for row in rendered:
        output.append(
            "| " + " | ".join(padded(value, widths[index]) for index, value in enumerate(row)) + " |"
        )
    output.append(separator)
    return "\n".join(output)


def fmt_number(value):
    return "-" if value is None or not math.isfinite(value) else f"{value:.3f}"


def violates_negative_expectation(observation, candidates):
    forbidden = set(observation.get("expect_absent", []))
    if forbidden:
        return any(candidate.get("text") in forbidden for candidate in candidates)
    return bool(candidates)


def print_case_table(observations, nonterminal_filter=True):
    rows = []
    for observation in observations:
        candidate = best_candidate(observation, nonterminal_filter)
        actual_texts = {item.get("text") for item in observation["result"]}
        actual_typo_texts = {
            item.get("text") for item in observation["actual_typo_candidates"]
        }
        expected = observation["expect"]
        forbidden = observation.get("expect_absent", [])
        if expected:
            expectation = "yes" if expected in actual_texts else "no"
        elif forbidden:
            expectation = "yes" if actual_texts.isdisjoint(forbidden) else "no"
        else:
            expectation = "-"
        rows.append(
            [
                observation["input"],
                observation["length"],
                observation["path"],
                fmt_number(observation["literal_best_per_mora"]),
                fmt_number(observation["literal_whole_best_per_mora"]),
                observation["literal_whole_best_text"] or "-",
                (observation["debug"].get("selection_gate") or {}).get("gate", "-"),
                candidate["text"] if candidate else "-",
                fmt_number(per_mora_diff(observation, candidate)),
                "yes" if actual_typo_texts else "no",
                expectation,
                observation["category"],
            ]
        )
    print("\nCase observations")
    print(
        ascii_table(
            [
                "input", "len", "path", "literal/mora", "whole/mora", "whole text",
                "gate", "best typo", "diff/mora", "accepted", "expectation", "category",
            ],
            rows,
        )
    )


def sweep_counts(observations, margins, sweep_kind, nonterminal_filter=True):
    rows = []
    positives = [item for item in observations if item["kind"] == "positive"]
    negatives = [item for item in observations if item["kind"] != "positive"]
    if sweep_kind == "short":
        positives = [item for item in positives if item["path"] == "short"]
        negatives = [item for item in negatives if item["path"] == "short"]
    else:
        positives = [item for item in positives if item["path"] == "long"]
        negatives = [item for item in negatives if item["path"] == "long"]

    for decimal_value in margins:
        value = float(decimal_value)
        true_positives = 0
        false_positives = 0
        for observation in positives:
            selected = replay(
                observation,
                short_margin=value if sweep_kind == "short" else CURRENT_SHORT_MARGIN,
                long_bar=value if sweep_kind == "long" else CURRENT_LONG_BAR,
                nonterminal_filter=nonterminal_filter,
            )
            if any(item["text"] == observation["expect"] for item in selected):
                true_positives += 1
        for observation in negatives:
            selected = replay(
                observation,
                short_margin=value if sweep_kind == "short" else CURRENT_SHORT_MARGIN,
                long_bar=value if sweep_kind == "long" else CURRENT_LONG_BAR,
                nonterminal_filter=nonterminal_filter,
            )
            if violates_negative_expectation(observation, selected):
                false_positives += 1
        rows.append([str(decimal_value), f"{true_positives}/{len(positives)}", f"{false_positives}/{len(negatives)}"])
    return rows


def short_path_score(observations, **replay_options):
    positives = [
        item for item in observations
        if item["kind"] == "positive" and item["path"] == "short"
    ]
    negatives = [
        item for item in observations
        if item["kind"] != "positive" and item["path"] == "short"
    ]
    true_positives = sum(
        any(candidate["text"] == item["expect"] for candidate in replay(item, **replay_options))
        for item in positives
    )
    false_positives = sum(
        violates_negative_expectation(item, replay(item, **replay_options))
        for item in negatives
    )
    return true_positives, len(positives), false_positives, len(negatives)


def solid_sweep_counts(
    observations, solid_values, improvement_values, nonterminal_filter=True
):
    rows = []
    for solid_decimal in solid_values:
        for improvement_decimal in improvement_values:
            score = short_path_score(
                observations,
                solid_literal_per_mora=float(solid_decimal),
                solid_literal_improvement=float(improvement_decimal),
                nonterminal_filter=nonterminal_filter,
            )
            rows.append([
                str(solid_decimal),
                str(improvement_decimal),
                f"{score[0]}/{score[1]}",
                f"{score[2]}/{score[3]}",
            ])
    return rows


def minimum_length_sweep_counts(observations, minimum_lengths, nonterminal_filter=True):
    rows = []
    for minimum_length in minimum_lengths:
        score = short_path_score(
            observations,
            minimum_input_length=minimum_length,
            nonterminal_filter=nonterminal_filter,
        )
        rows.append([
            minimum_length,
            f"{score[0]}/{score[1]}",
            f"{score[2]}/{score[3]}",
        ])
    return rows


def print_category_table(observations, nonterminal_filter=True):
    groups = {}
    for observation in observations:
        label = "positive" if observation["kind"] == "positive" else "negative"
        candidate = best_candidate(observation, nonterminal_filter)
        difference = per_mora_diff(observation, candidate)
        if difference is not None:
            groups.setdefault((label, observation["category"]), []).append(difference)
    rows = []
    for (label, category), values in sorted(groups.items()):
        rows.append(
            [label, category, len(values), fmt_number(min(values)), fmt_number(max(values)), fmt_number(statistics.median(values))]
        )
    print("\nPer-category per-mora differences")
    print(ascii_table(["set", "category", "n", "min", "max", "median"], rows))


def main():
    args = parse_args()
    try:
        short_margins = decimal_sweep(args.sweep)
        long_bars = decimal_sweep(args.sweep_bar)
        solid_values = decimal_sweep(args.sweep_solid)
        improvement_values = decimal_sweep(args.sweep_improve)
        minimum_length_decimals = decimal_sweep(args.sweep_min_length)
        if any(value != value.to_integral_value() for value in minimum_length_decimals):
            raise argparse.ArgumentTypeError("minimum input lengths must be integers")
        minimum_lengths = [int(value) for value in minimum_length_decimals]
    except argparse.ArgumentTypeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    cases_path = resolve_from_root(args.cases)
    with cases_path.open("r", encoding="utf-8") as handle:
        case_data = json.load(handle)
    cases = [(case, "positive") for case in case_data["positives"]]
    cases.extend((case, "negative") for case in case_data["negatives"])
    for sentence in case_data["clean_sentences"]:
        if isinstance(sentence, str):
            case = {"input": sentence, "category": "clean_sentences"}
        else:
            case = dict(sentence)
            case.setdefault("category", "clean_sentences")
        cases.append((case, "clean"))

    try:
        engine, dll_path = load_engine(args.dll)
    except (FileNotFoundError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    observations = []
    with tempfile.TemporaryDirectory(prefix="azookey-typo-calibration-") as memory:
        if engine.Initialize(b"", memory.encode("utf-8")) != 1:
            print("error: Initialize failed", file=sys.stderr)
            return 1
        try:
            engine.SetZenzaiEnabled(False)
            engine.SetTypoCorrectionEnabled(True)
            engine.SetTypoCorrectionBudget(args.budget)
            for index, (case, kind) in enumerate(cases, 1):
                print(f"[{index}/{len(cases)}] {case['input']}", file=sys.stderr)
                result, raw_log = convert_with_debug(engine, case["input"])
                observations.append(enrich_observation(case, kind, result, raw_log))
        finally:
            engine.Shutdown()

    print(f"DLL: {dll_path}")
    print(f"Cases: {cases_path}  budget={args.budget}")
    nonterminal_filter = not args.no_nonterminal_filter
    print(
        "Replay nonterminal filter: "
        + ("enabled" if nonterminal_filter else "disabled (--no-nonterminal-filter)")
    )
    print_case_table(observations, nonterminal_filter)
    scopes = [
        ("input length >= 3", [item for item in observations if item["length"] >= 3]),
        ("all inputs", observations),
    ]
    for scope_name, scope_observations in scopes:
        print(f"\nCalibration scope: {scope_name}")
        print("\nShort-path signed per-mora margin sweep")
        print(ascii_table(
            ["margin", "expected positives", "false-positive inputs"],
            sweep_counts(scope_observations, short_margins, "short", nonterminal_filter),
        ))
        print("\nLong-path improvement-bar sweep")
        print(ascii_table(
            ["bar", "expected positives", "false-positive inputs"],
            sweep_counts(scope_observations, long_bars, "long", nonterminal_filter),
        ))
        print("\nShort-path solid-literal 2D sweep")
        print(ascii_table(
            ["solid/mora", "required improvement", "expected positives", "false-positive inputs"],
            solid_sweep_counts(
                scope_observations, solid_values, improvement_values, nonterminal_filter
            ),
        ))
        print("\nShort-path minimum-input-length sweep")
        print(ascii_table(
            ["minimum length", "expected positives", "false-positive inputs"],
            minimum_length_sweep_counts(
                scope_observations, minimum_lengths, nonterminal_filter
            ),
        ))
        print_category_table(scope_observations, nonterminal_filter)

    if args.json_output:
        output_path = resolve_from_root(args.json_output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "dll": str(dll_path),
            "cases": str(cases_path),
            "budget": args.budget,
            "short_sweep": [str(value) for value in short_margins],
            "long_bar_sweep": [str(value) for value in long_bars],
            "solid_literal_sweep": [str(value) for value in solid_values],
            "solid_improvement_sweep": [str(value) for value in improvement_values],
            "minimum_input_length_sweep": minimum_lengths,
            "nonterminal_filter": nonterminal_filter,
            "observations": observations,
        }
        with output_path.open("w", encoding="utf-8", newline="\n") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        print(f"\nRaw data: {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
