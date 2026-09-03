#!/usr/bin/env python3
"""Generate the Swift IPADIC feature-to-CID lookup table."""

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INPUT_PATH = ROOT / "scripts" / "data" / "ipadic-left-id.def"
OUTPUT_PATH = (
    ROOT
    / "src"
    / "swift-engine"
    / "Sources"
    / "azookey-engine"
    / "IpadicCidTable.swift"
)

# Mozc user_pos.def represents this generic POS with the concrete surface
# "ね". Keep the same connection ID instead of choosing the smallest surface
# variant when ipadic-left-id.def has no seventh-column "*" row.
FEATURE_CID_OVERRIDES = {
    "助詞,終助詞,*,*,*,*": 279,
}


def swift_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def load_tables(path: Path) -> tuple[dict[str, int], dict[int, str]]:
    candidates: dict[str, list[tuple[int, bool]]] = {}
    cid_to_feature: dict[int, str] = {}
    with path.open(encoding="utf-8") as source:
        for line_number, raw_line in enumerate(source, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                cid_text, features_text = line.split(maxsplit=1)
                cid = int(cid_text)
            except ValueError as error:
                raise ValueError(f"{path}:{line_number}: invalid line: {line!r}") from error

            features = features_text.split(",")
            if len(features) != 7:
                raise ValueError(
                    f"{path}:{line_number}: expected 7 features, got {len(features)}"
                )
            key = ",".join(features[:6])
            candidates.setdefault(key, []).append((cid, features[6] == "*"))
            cid_to_feature[cid] = key

    result: dict[str, int] = {}
    for key, rows in candidates.items():
        generic_cids = [cid for cid, is_generic in rows if is_generic]
        if generic_cids:
            result[key] = min(generic_cids)
        else:
            fallback_cid = min(cid for cid, _ in rows)
            print(
                f"warning: no generic row for {ascii(key)}; falling back to CID {fallback_cid}",
                file=sys.stderr,
            )
            result[key] = fallback_cid
    result.update(FEATURE_CID_OVERRIDES)
    return result, cid_to_feature


def render(feature_to_cid: dict[str, int], cid_to_feature: dict[int, str]) -> str:
    feature_rows = "\n".join(
        f'        "{swift_string(feature)}": {cid},'
        for feature, cid in sorted(feature_to_cid.items())
    )
    cid_rows = "\n".join(
        f'        {cid}: "{swift_string(feature)}",'
        for cid, feature in sorted(cid_to_feature.items())
    )
    return f"""// This file is generated. Do not edit it directly.
// Regenerate with: python3 scripts/gen_ipadic_cid_table.py
//
// IPADIC copyright: Copyright 2000, 2001, 2002, 2003 Nara Institute of
// Science and Technology (NAIST). All Rights Reserved. Use, reproduction,
// and distribution are permitted subject to scripts/data/ipadic-COPYING;
// the software is provided without warranty. A large portion originates
// from ICOT Free Software and remains subject to the terms in that file.

enum IpadicCidTable {{
    static let featureToCid: [String: Int] = [
{feature_rows}
    ]

    static let cidToFeature: [Int: String] = [
{cid_rows}
    ]
}}
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="write generated Swift source to stdout without changing the checked-in file",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    feature_to_cid, cid_to_feature = load_tables(INPUT_PATH)
    generated = render(feature_to_cid, cid_to_feature)
    if args.stdout:
        sys.stdout.buffer.write(generated.encode("utf-8"))
        return
    OUTPUT_PATH.write_text(generated, encoding="utf-8", newline="\n")
    print(
        f"generated {len(feature_to_cid)} feature entries and "
        f"{len(cid_to_feature)} CID entries: {OUTPUT_PATH}"
    )


if __name__ == "__main__":
    main()
