#!/usr/bin/env bash
# Runs KeyDeckKit tests with coverage and writes SonarCloud generic coverage XML
# to build/sonar/coverage.xml (paths relative to the repo root).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/KeyDeckKit"
OUT="$ROOT/build/sonar"
mkdir -p "$OUT"

swift test --package-path "$PKG" --enable-code-coverage

BIN="$(swift build --package-path "$PKG" --show-bin-path)"
PROFDATA="$BIN/codecov/default.profdata"
XCTEST="$(find "$BIN" -maxdepth 1 -name '*.xctest' | head -n1)"
# On macOS the .xctest is a bundle; the executable lives inside it.
if [ -d "$XCTEST" ]; then
  XCTEST="$XCTEST/Contents/MacOS/$(basename "$XCTEST" .xctest)"
fi

xcrun llvm-cov export -format=lcov \
  -instr-profile "$PROFDATA" "$XCTEST" \
  -ignore-filename-regex='(\.build|Tests)/' > "$OUT/coverage.lcov"

python3 -I - "$OUT/coverage.lcov" "$ROOT" > "$OUT/coverage.xml" <<'PY'
import os, sys
from xml.sax.saxutils import quoteattr
lcov, root = sys.argv[1], sys.argv[2]
files, cur = {}, None
for line in open(lcov):
    line = line.strip()
    if line.startswith("SF:"):
        cur = os.path.relpath(line[3:], root); files.setdefault(cur, {})
    elif line.startswith("DA:") and cur:
        n, hits = line[3:].split(",")[:2]
        files[cur][int(n)] = files[cur].get(int(n), 0) + int(hits)
print('<coverage version="1">')
for path, lines in sorted(files.items()):
    print(f'  <file path={quoteattr(path)}>')
    for n in sorted(lines):
        print(f'    <lineToCover lineNumber="{n}" covered="{str(lines[n] > 0).lower()}"/>')
    print('  </file>')
print('</coverage>')
PY

echo "Wrote $OUT/coverage.xml"
