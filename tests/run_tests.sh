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

check_eq "namespace-visible objects" 18 "$(stat_of "$WORK/sum.txt" visible)"
check_eq "internal objects skipped"  1  "$(stat_of "$WORK/sum.txt" internal)"
check_eq "OST objects skipped"       1  "$(stat_of "$WORK/sum.txt" 'ost-obj')"
check_eq "agent inodes skipped"      1  "$(stat_of "$WORK/sum.txt" agent)"
# badincompat1 + released1: LMAI_RELEASED is not in LMA_INCOMPAT_SUPP either.
check_eq "unsupported incompat -> bad" 2 "$(stat_of "$WORK/sum.txt" bad)"

echo "==> default scan emits only visible objects"
"$SCAN" "$IMG" >"$WORK/vis.txt" 2>"$WORK/vissum.txt"
check_eq "emitted == visible" 18 "$(stat_of "$WORK/vissum.txt" emitted)"
check_eq "no zero FIDs emitted" 0 "$(grep -c '^\[0x0:0x0:0x0\]' "$WORK/vis.txt")"

echo "==> FID decoding"
check_eq "normal-sequence FIDs" 18 \
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

echo "==> tier-0 filters, lfs find spelling (docs/filter-levels.md §2)"
# The legacy flags above and these must compile to the same predicate.
check_eq "--projid 1999 == -p 1999" 1 \
	"$("$SCAN" --projid 1999 "$IMG" 2>/dev/null | wc -l)"
check_eq "--atime +1y == -a 31536000" 1 \
	"$("$SCAN" --atime +1y "$IMG" 2>/dev/null | wc -l)"
check_eq "--dev-blocks +16 == -b 16" 0 \
	"$("$SCAN" --dev-blocks +16 "$IMG" 2>/dev/null | wc -l)"
check_eq "--type d finds the striped directory" 1 \
	"$("$SCAN" --type d "$IMG" 2>/dev/null | wc -l)"
check_eq "--type f matches all but the striped dir" 17 \
	"$("$SCAN" --type f "$IMG" 2>/dev/null | wc -l)"
check_eq "--uid 0 matches every object" 18 \
	"$("$SCAN" --uid 0 "$IMG" 2>/dev/null | wc -l)"
check_eq "--links 1 matches the regular files" 17 \
	"$("$SCAN" --links 1 "$IMG" 2>/dev/null | wc -l)"
# /MODE is "any of these bits", and 0755 shares 0644's bits, so the directory
# matches too; exact 0644 is the discriminating form.
check_eq "--perm /0644 is any-of, so the dir matches" 18 \
	"$("$SCAN" --perm /0644 "$IMG" 2>/dev/null | wc -l)"
check_eq "--perm 0644 is exact, so it does not" 17 \
	"$("$SCAN" --perm 0644 "$IMG" 2>/dev/null | wc -l)"
check_eq "--attrs i finds the immutable inode" 1 \
	"$("$SCAN" --attrs i "$IMG" 2>/dev/null | wc -l)"
check_eq "--attrs E reads EXT4_ENCRYPT_FL" 1 \
	"$("$SCAN" --attrs E "$IMG" 2>/dev/null | wc -l)"
check_eq "--attrs ^i excludes it" 17 \
	"$("$SCAN" --attrs '^i' "$IMG" 2>/dev/null | wc -l)"
check_eq "\`!\` negates: ! --type f" 1 \
	"$("$SCAN" '!' --type f "$IMG" 2>/dev/null | wc -l)"
check_eq "a bare trailing ! is refused" 2 \
	"$("$SCAN" "$IMG" '!' >/dev/null 2>&1; echo $?)"

echo "==> the size trap: --blocks is not the MDT's own block count (§4)"
# striped1 is a 2-stripe file with 2 GiB in trusted.som and a handful of
# blocks in its own inode -- exactly the shape §4.3 predicts for a real MDT.
check_eq "--dev-blocks +1G matches nothing" 0 \
	"$("$SCAN" --dev-blocks +1G "$IMG" 2>/dev/null | wc -l)"
check_eq "--blocks +1G finds it via SOM" 1 \
	"$("$SCAN" --blocks +1G "$IMG" 2>/dev/null | wc -l)"
check_eq "--size +1G finds it via SOM" 1 \
	"$("$SCAN" --size +1G "$IMG" 2>/dev/null | wc -l)"
check_eq "and reports the SOM size, not i_size" 1 \
	"$("$SCAN" --size +1G "$IMG" 2>/dev/null | grep -c 'size=2147483648')"
# An unstriped file's own i_size IS authoritative -- the other half of §4.
check_eq "unstriped file answered from i_size" 1 \
	"$("$SCAN" --size +100K "$IMG" 2>/dev/null | grep -c 'size=200000')"

echo "==> the third outcome: undecided (§4.4)"
# striped_nosom and widelov1 are striped with no trusted.som: an MDT-only scan
# cannot say whether they match a size test, and must not claim they do not.
"$SCAN" -q --size +0 "$IMG" >/dev/null 2>"$WORK/unk.txt"
check_eq "striped, SOM-less objects are undecided" 2 \
	"$(stat_of "$WORK/unk.txt" undecided)"
check_eq "and are not emitted by default" 16 \
	"$(stat_of "$WORK/unk.txt" emitted)"
check_eq "-u emits them tagged" 2 \
	"$("$SCAN" -u --size +0 "$IMG" 2>/dev/null | grep -c '+unknown')"

echo "==> tier-1 layout predicates (§5.2 -- none of these worked before)"
check_eq "--stripe-count 2" 1 \
	"$("$SCAN" --stripe-count 2 "$IMG" 2>/dev/null | wc -l)"
check_eq "--stripe-count +1 (2- and 60-stripe)" 2 \
	"$("$SCAN" --stripe-count +1 "$IMG" 2>/dev/null | wc -l)"
check_eq "--stripe-size +2M" 1 \
	"$("$SCAN" --stripe-size +2M "$IMG" 2>/dev/null | wc -l)"
check_eq "--pool fast (LOV v3)" 1 \
	"$("$SCAN" --pool fast "$IMG" 2>/dev/null | wc -l)"
# pooled1 is on OST 5, and widelov1 spans 0-59, so both match.
check_eq "--ost 5 (pooled1 and the wide-striped file)" 2 \
	"$("$SCAN" --ost 5 "$IMG" 2>/dev/null | wc -l)"
# lfs.c:7804 handles -i and -O in one case: they are one predicate, not two.
check_eq "--stripe-index is the same predicate as --ost" 2 \
	"$("$SCAN" --stripe-index 5 "$IMG" 2>/dev/null | wc -l)"
check_eq "--ost 3,7 (a list)" 3 \
	"$("$SCAN" --ost 3,7 "$IMG" 2>/dev/null | wc -l)"
# Every object with OST stripes: striped1, striped_nosom, pooled1, comp1,
# widelov1.  hsmrel1 is released and has none left to look at.
check_eq "--ost 0-59 (a range) finds every striped object" 5 \
	"$("$SCAN" --ost 0-59 "$IMG" 2>/dev/null | wc -l)"
check_eq "--layout released" 1 \
	"$("$SCAN" --layout released "$IMG" 2>/dev/null | wc -l)"
check_eq "--layout mdt finds the DoM component" 1 \
	"$("$SCAN" --layout mdt "$IMG" 2>/dev/null | wc -l)"
check_eq "--comp-count 2 (composite layout)" 1 \
	"$("$SCAN" --comp-count 2 "$IMG" 2>/dev/null | wc -l)"
check_eq "a released file's size comes from the MDT" 1 \
	"$("$SCAN" --layout released --size -1K "$IMG" 2>/dev/null | wc -l)"

echo "==> tier-1 name and directory striping"
check_eq "--name matches a linkea entry" 1 \
	"$("$SCAN" --name 'report*' "$IMG" 2>/dev/null | wc -l)"
check_eq "--name matches the second link too" 1 \
	"$("$SCAN" --name second_link.txt "$IMG" 2>/dev/null | wc -l)"
check_eq "--name misses what is not there" 0 \
	"$("$SCAN" --name nosuchfile "$IMG" 2>/dev/null | wc -l)"
check_eq "--mdt-count 4 (striped directory)" 1 \
	"$("$SCAN" --mdt-count 4 "$IMG" 2>/dev/null | wc -l)"
check_eq "--mdt-hash fnv_1a_64" 1 \
	"$("$SCAN" --mdt-hash fnv_1a_64 "$IMG" 2>/dev/null | wc -l)"
check_eq "--mdt-hash crush misses" 0 \
	"$("$SCAN" --mdt-hash crush "$IMG" 2>/dev/null | wc -l)"

echo "==> the demand mask: a tier-0 query pays for no xattr (§9)"
"$SCAN" -q --type f "$IMG" >/dev/null 2>"$WORK/t0only.txt"
check_eq "no external EA read for a tier-0 filter" 0 \
	"$(stat_of "$WORK/t0only.txt" 'tier-2 (read)')"
# widelov1's 1472-byte LOV lives in an external block, so a LOV predicate has
# to pay for it -- and M9 says libext2fs fetches it transparently.
"$SCAN" -q --stripe-count +0 "$IMG" >/dev/null 2>"$WORK/t1lov.txt"
check_eq "a LOV filter pays for the one spilled object" 1 \
	"$(stat_of "$WORK/t1lov.txt" 'tier-2 (read)')"
check_eq "and still answers it correctly (M9)" 1 \
	"$("$SCAN" --stripe-count 60 "$IMG" 2>/dev/null | grep -c 'stripes=60')"

echo "==> filter ordering: rejected objects cost no LMA parse"
# With projid=1999 only one object survives the tier-0 filter, so exactly one
# object should reach classification.  Everything else is counted as filtered.
"$SCAN" -p 1999 "$IMG" >/dev/null 2>"$WORK/f.txt"
check_eq "filtered before classification" 26 "$(stat_of "$WORK/f.txt" 'filtered (t0)')"
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

echo "==> the OSD benchmark sweep's own logic (no kernel, no lab needed)"
# bench_osd_sweep.sh can only run against a mounted MDT as root, so the parts
# that can be wrong on any machine -- report-line parsing, median selection,
# and the readback-derived labels -- are checked here instead of never.
if "$HERE/bench_osd_sweep.sh" --self-test > "$WORK/sweep.txt" 2>&1; then
	check_eq "sweep parser and median self-test" PASS PASS
else
	check_eq "sweep parser and median self-test" PASS FAILED
	sed -n '/FAIL/p' "$WORK/sweep.txt"
fi
# The dry run exercises the matrix, the label construction and the identity
# check without touching a tunable.
sweep_rows=$("$HERE/bench_osd_sweep.sh" --dry-run --ra "0 32" --threads "1 4" \
	--passes 1 2>/dev/null | grep -c '^WARM ')
check_eq "sweep dry run emits one row per (ra, threads)" 4 "$sweep_rows"
check_eq "every sweep row carries an ra= label" 4 \
	"$("$HERE/bench_osd_sweep.sh" --dry-run --ra "0 32" --threads "1 4" \
	   --passes 1 2>/dev/null | grep -c '^WARM bp=[01] ra=[0-9]')"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
