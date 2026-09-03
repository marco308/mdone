#!/usr/bin/env python3
"""Merge compiler-extracted strings into a String Catalog.

Xcode's IDE syncs `.xcstrings` from the `.stringsdata` that swiftc emits under
`SWIFT_EMIT_LOC_STRINGS`. `xcodebuild` does not: it writes the `.stringsdata`
and stops. This script does the sync step, so the catalogs can be refreshed
from the command line and in CI.

Merge rules, which exist so a translator's work is never collateral damage:
  - a newly seen key is added with no translations;
  - an existing key keeps its `comment`, `localizations` and `variations`;
  - a key the compiler no longer finds is marked `stale` rather than deleted,
    because the string may just be behind a platform the run did not build;
  - `extractionState: manual` entries are left alone entirely.
"""

import json
import subprocess
import sys
from pathlib import Path


def read_stringsdata(path: Path) -> dict:
    """`.stringsdata` is a binary plist; plutil is the dependency-free reader."""
    raw = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        capture_output=True, check=True,
    ).stdout
    return json.loads(raw)


def extract(build_dirs: list[Path]) -> dict[str, str]:
    """Collect key -> comment for every string the compiler found."""
    found: dict[str, str] = {}
    for build_dir in build_dirs:
        for data_file in build_dir.rglob("*.stringsdata"):
            for table, entries in read_stringsdata(data_file).get("tables", {}).items():
                if table != "Localizable":
                    continue
                for entry in entries:
                    key = entry.get("key")
                    if key is None:
                        continue
                    comment = entry.get("comment") or ""
                    # First non-empty comment wins; a later empty one must not
                    # wipe a good one from another call site.
                    if key not in found or (comment and not found[key]):
                        found[key] = comment
    return found


def merge(catalog_path: Path, found: dict[str, str]) -> tuple[int, int, int]:
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})
    added = revived = stale = 0

    for key, comment in sorted(found.items()):
        entry = strings.get(key)
        if entry is None:
            entry = {}
            if comment:
                entry["comment"] = comment
            strings[key] = entry
            added += 1
            continue
        if entry.get("extractionState") == "stale":
            del entry["extractionState"]
            revived += 1
        if comment and "comment" not in entry:
            entry["comment"] = comment

    for key, entry in strings.items():
        if key in found or entry.get("extractionState") == "manual":
            continue
        if entry.get("extractionState") != "stale":
            entry["extractionState"] = "stale"
            stale += 1

    catalog["strings"] = {k: strings[k] for k in sorted(strings)}
    write_catalog(catalog_path, catalog)
    return added, revived, stale


def write_catalog(path: Path, catalog: dict) -> None:
    """Write in Xcode's own `.xcstrings` style.

    Sorted keys, 2-space indent, `" : "` between key and value, and a trailing
    newline. Matching it matters: otherwise the first time someone opens the
    catalog in Xcode it rewrites the whole file and the real change is buried
    in a whitespace diff.
    """
    path.write_text(
        json.dumps(catalog, indent=2, ensure_ascii=False, separators=(",", " : ")) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: merge-stringsdata.py <catalog.xcstrings> <build-dir> [build-dir ...]",
              file=sys.stderr)
        return 2

    catalog_path = Path(sys.argv[1])
    build_dirs = [Path(p) for p in sys.argv[2:]]
    missing = [d for d in build_dirs if not d.is_dir()]
    if missing:
        print(f"error: no such build directory: {missing[0]}", file=sys.stderr)
        return 1

    found = extract(build_dirs)
    if not found:
        print(f"error: no extracted strings under {build_dirs[0]}; did the build run?",
              file=sys.stderr)
        return 1

    added, revived, stale = merge(catalog_path, found)
    print(f"{catalog_path}: {len(found)} extracted, "
          f"{added} added, {revived} revived, {stale} newly stale")
    return 0


if __name__ == "__main__":
    sys.exit(main())
