#!/bin/bash
# Regression tests for the LFU ldiskfs Device Input Scanner prototype.
#
# Builds a synthetic MDT-like image (tests/mkimage.sh) and asserts the
# classification ladder (design §5) and tier-0 filter ordering (design §7).
#
# Usage: tests/run_tests.sh [path-to-scanner]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
SCAN="${1:-$ROOT/build/lfu-scan-ldiskfs}"
WORK="$(mktemp -d)"
IMG="$WORK/mdt-test.img"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; printf '        %s\n' "$2"; fail=$((fail+1)); }

check_eq() {
	local desc="$1" want="$2" got="$3"
	if [ "$want" = "$got" ]; then ok "$desc"; else bad "$desc" "expected '$want', got '$got'"; fi
}

# stat_of <summary-file> <label>  -> value from a "label : value" summary line.
# Uses fixed-string matching: labels such as "filtered (t0)" contain regex
# metacharacters.
stat_of() {
	grep -F -- "$2" "$1" | grep -F ':' | head -1 |
		sed -E 's/^[^:]*: *//' | awk '{print $1}'
}

# kv_of <summary-file> <key>  -> value from a "key=value" pair, e.g. the
# "skipped: csum=0 validate=0" line.
kv_of() {
	sed -nE "s/.*(^|[[:space:]])$2=([0-9]+).*/\2/p" "$1" | head -1
}

if [ ! -x "$SCAN" ]; then
	echo "scanner not built: $SCAN" >&2
	echo "run: make E2FSROOT=<extracted libext2fs-dev tree>" >&2
	exit 1
fi

echo "==> building test image"
"$HERE/mkimage.sh" "$IMG" 64M >/dev/null || { echo "mkimage failed" >&2; exit 1; }

echo "==> classification (design §5)"
"$SCAN" -i "$IMG" >"$WORK/out.txt" 2>"$WORK/sum.txt"

check_eq "namespace-visible objects" 9  "$(stat_of "$WORK/sum.txt" visible)"
check_eq "internal objects skipped"  1  "$(stat_of "$WORK/sum.txt" internal)"
check_eq "OST objects skipped"       1  "$(stat_of "$WORK/sum.txt" 'ost-obj')"
check_eq "agent inodes skipped"      1  "$(stat_of "$WORK/sum.txt" agent)"
# badincompat1 + released1: LMAI_RELEASED is not in LMA_INCOMPAT_SUPP either.
check_eq "unsupported incompat -> bad" 2 "$(stat_of "$WORK/sum.txt" bad)"

echo "==> default scan emits only visible objects"
"$SCAN" "$IMG" >"$WORK/vis.txt" 2>"$WORK/vissum.txt"
check_eq "emitted == visible" 9 "$(stat_of "$WORK/vissum.txt" emitted)"
check_eq "no zero FIDs emitted" 0 "$(grep -c '^\[0x0:0x0:0x0\]' "$WORK/vis.txt")"

echo "==> FID decoding"
check_eq "normal-sequence FIDs" 9 \
	"$(grep -c '^\[0x200000400:' "$WORK/vis.txt")"
check_eq "encrypted flag surfaced" 1 "$(grep -c '+encrypted' "$WORK/vis.txt")"

echo "==> tier-0 filters (design §7)"
check_eq "projid=1999 matches one object" 1 \
	"$("$SCAN" -p 1999 "$IMG" 2>/dev/null | grep -c 'projid=1999')"
check_eq "projid=1 matches nothing" 0 \
	"$("$SCAN" -p 1 "$IMG" 2>/dev/null | wc -l)"
check_eq "atime older than 1 year matches one" 1 \
	"$("$SCAN" -a 31536000 "$IMG" 2>/dev/null | wc -l)"
check_eq "blocks > 16 matches nothing (all small)" 0 \
	"$("$SCAN" -b 16 "$IMG" 2>/dev/null | wc -l)"

echo "==> filter ordering: rejected objects cost no LMA parse"
# With projid=1999 only one object survives the tier-0 filter, so exactly one
# object should reach classification.  Everything else is counted as filtered.
"$SCAN" -p 1999 "$IMG" >/dev/null 2>"$WORK/f.txt"
check_eq "filtered before classification" 17 "$(stat_of "$WORK/f.txt" 'filtered (t0)')"
check_eq "only survivor classified visible" 1 "$(stat_of "$WORK/f.txt" visible)"

echo "==> torn-read defences report cleanly on a quiescent image"
check_eq "no checksum failures"      0 "$(kv_of "$WORK/sum.txt" csum)"
check_eq "no validation failures"    0 "$(kv_of "$WORK/sum.txt" validate)"

echo "==> the in-kernel block parser, against images mke2fs/debugfs wrote"
if "$(dirname "$0")/blockparse_test.sh" > "$WORK/bp.txt" 2>&1; then
	check_eq "block parser matches debugfs on every field" PASS \
		"$(tail -1 "$WORK/bp.txt")"
else
	check_eq "block parser matches debugfs on every field" PASS FAILED
	sed -n '/FAIL/p' "$WORK/bp.txt"
fi

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
