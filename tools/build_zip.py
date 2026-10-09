#!/usr/bin/env python3
"""Package tracked working-tree files beneath MWI_[version]/."""
import argparse
import re
import subprocess
import zipfile
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    version = re.search(r"^# Mirishita Waydroid Installer \(MWI\) ([0-9]+\.[0-9]+\.[0-9]+)\s*$",
                        (root / "README.md").read_text(encoding="utf-8"), re.MULTILINE)
    if version is None:
        raise SystemExit("README version not found")
    name = f"MWI_{version.group(1)}"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=root / "dist")
    args = parser.parse_args()
    entries = subprocess.check_output(
        ["git", "ls-files", "--stage", "-z"], cwd=root).split(b"\0")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output = args.output_dir / f"{name}.zip"
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for entry in entries:
            if not entry:
                continue
            metadata, relative = entry.decode("utf-8").split("\t", 1)
            mode, _, stage = metadata.split()
            if stage != "0" or mode not in ("100644", "100755"):
                raise SystemExit(f"Unsupported Git entry: {relative}")
            info = zipfile.ZipInfo(f"{name}/{relative}")
            info.create_system = 3
            info.external_attr = int(mode, 8) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, (root / relative).read_bytes())
    print(output)


if __name__ == "__main__":
    main()
