#!/usr/bin/env python3
"""Check that the IPADIC source and generated Swift table are in sync."""

import hashlib
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_SOURCE = ROOT / "scripts" / "data" / "ipadic-left-id.def"
MOZC_SOURCE = ROOT / "mozc" / "src" / "data" / "azookey" / "ipadic-left-id.def"
GENERATOR = ROOT / "scripts" / "gen_ipadic_cid_table.py"
CHECKED_IN = (
    ROOT
    / "src"
    / "swift-engine"
    / "Sources"
    / "azookey-engine"
    / "IpadicCidTable.swift"
)


def normalize_newlines(data: bytes) -> bytes:
    # Git on the Windows CI runner may check files out with CRLF (core.autocrlf), and
    # the submodule can use different attributes from the main repository. Compare
    # content, not line endings.
    return data.replace(b"\r\n", b"\n")


def sha256(path: Path) -> str:
    return hashlib.sha256(normalize_newlines(path.read_bytes())).hexdigest()


def main() -> int:
    failed = False
    if sha256(SCRIPT_SOURCE) != sha256(MOZC_SOURCE):
        failed = True
        print("ERROR: IPADIC source files differ.", file=sys.stderr)
        print(
            "Fix: synchronize scripts/data/ipadic-left-id.def with "
            "mozc/src/data/azookey/ipadic-left-id.def, then run "
            "python scripts/gen_ipadic_cid_table.py",
            file=sys.stderr,
        )

    process = subprocess.run(
        [sys.executable, str(GENERATOR), "--stdout"],
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if process.returncode != 0:
        failed = True
        print("ERROR: IPADIC table generator failed.", file=sys.stderr)
        sys.stderr.buffer.write(process.stderr)
    elif normalize_newlines(process.stdout) != normalize_newlines(CHECKED_IN.read_bytes()):
        failed = True
        print("ERROR: IpadicCidTable.swift is stale.", file=sys.stderr)
        print(
            "Fix: run python scripts/gen_ipadic_cid_table.py and check in the result.",
            file=sys.stderr,
        )

    if failed:
        return 1
    print("OK: IPADIC sources and generated Swift table are consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
