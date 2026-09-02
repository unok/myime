"""Check that installer DLL entries match the canonical PowerShell lists.

Targets copy-*.ps1 lists and installer_oss_64bit.wxs; build-*.bat is excluded because build-x64.bat consumes -ListOnly.
Missing inputs (e.g. the mozc submodule is not initialized) exit 2 with a
remediation hint instead of a generic OSError.
Usage: python scripts/ci/check-dll-lists.py
"""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
LIST_SCRIPTS = (
    ROOT / "scripts" / "ci" / "copy-swift-runtime.ps1",
    ROOT / "scripts" / "ci" / "copy-llama-dlls.ps1",
)
WXS_PATH = ROOT / "mozc" / "src" / "win32" / "installer" / "installer_oss_64bit.wxs"


def find_powershell() -> str | None:
    """Return the preferred PowerShell executable, if available."""
    return shutil.which("pwsh") or shutil.which("powershell")


def read_canonical_names(powershell: str) -> set[str]:
    """Run each canonical list script without triggering its copy behavior."""
    # The engine itself is a Swift build artifact, not a copy-*.ps1 copy target.
    names: set[str] = {"azookey-engine.dll"}
    for script in LIST_SCRIPTS:
        result = subprocess.run(
            [
                powershell,
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
                "-ListOnly",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
            timeout=60,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"{script.name} -ListOnly failed with exit code {result.returncode}: "
                f"{result.stderr.strip()}"
            )
        names.update(line.strip() for line in result.stdout.splitlines() if line.strip())
    return names


def read_installer_names() -> set[str]:
    """Collect AzooKey payload DLL names from the WiX installer source."""
    root = ET.parse(WXS_PATH).getroot()
    names: set[str] = set()
    for element in root.iter():
        if element.tag.rsplit("}", 1)[-1] != "File":
            continue
        source = element.get("Source", "")
        name = element.get("Name", "")
        if "AzooKeyDllDir" in source and name.lower().endswith(".dll"):
            names.add(name)
    return names


def check_inputs_exist() -> bool:
    """Report missing input files up front so CI logs say how to fix them."""
    missing = [path for path in (*LIST_SCRIPTS, WXS_PATH) if not path.is_file()]
    for path in missing:
        print(f"ERROR: missing input: {path.relative_to(ROOT).as_posix()}")
    if WXS_PATH in missing:
        print('hint: run "git submodule update --init --recursive" '
              "(mozc submodule is not initialized)")
    return not missing


def main() -> int:
    if not check_inputs_exist():
        return 2

    powershell = find_powershell()
    if powershell is None:
        print("ERROR: neither pwsh nor powershell was found")
        return 2

    try:
        canonical = read_canonical_names(powershell)
        installer = read_installer_names()
    except (OSError, ET.ParseError, UnicodeError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}")
        return 2

    wxs_only = sorted(installer - canonical)
    ps1_only = sorted(canonical - installer)
    if wxs_only or ps1_only:
        print("ERROR: DLL lists do not match")
        print("wxs only:")
        for name in wxs_only:
            print(f"  {name}")
        print("ps1 only:")
        for name in ps1_only:
            print(f"  {name}")
        return 1

    print(f"DLL lists match ({len(canonical)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
