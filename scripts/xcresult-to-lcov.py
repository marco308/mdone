#!/usr/bin/env python3
"""Convert an .xcresult bundle's code coverage into an lcov tracefile.

Codecov cannot read the JSON that `xcrun xccov view --report --json` prints
(per-file percentages only, no line data), and `llvm-cov export` needs the
instrumented binaries plus a profdata that Xcode does not keep next to the
result bundle. The bundle itself carries line-level coverage, and
`xcrun xccov view --archive --json` dumps it for every file in one call.
This script turns that into lcov, which Codecov (and every other coverage
tool) understands.

Usage: xcresult-to-lcov.py <path.xcresult> [output.lcov]
Writes to stdout when no output path is given.
"""

import json
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write(__doc__)
        return 2

    bundle = sys.argv[1]
    result = subprocess.run(
        ["xcrun", "xccov", "view", "--archive", "--json", bundle],
        check=True,
        capture_output=True,
        text=True,
    )
    files = json.loads(result.stdout)

    out = []
    total_lines = total_hits = 0
    for path in sorted(files):
        found = hit = 0
        out.append(f"SF:{path}")
        for entry in files[path]:
            if not entry.get("isExecutable"):
                continue
            count = entry.get("executionCount", 0)
            out.append(f"DA:{entry['line']},{count}")
            found += 1
            hit += 1 if count > 0 else 0
        out.append(f"LF:{found}")
        out.append(f"LH:{hit}")
        out.append("end_of_record")
        total_lines += found
        total_hits += hit

    text = "\n".join(out) + "\n"
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)

    pct = (100.0 * total_hits / total_lines) if total_lines else 0.0
    sys.stderr.write(f"{len(files)} files, {total_hits}/{total_lines} lines ({pct:.1f}%)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
