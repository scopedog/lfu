#!/bin/bash
# The filter evaluator, along both of its build branches, on the same bytes.
#
# src/lfu_filter_eval.c is linked into the userspace scanners and #included
# into the lfu_ring kernel module; src/lfu_filter.h selects the kernel branch
# under __KERNEL__.  This compiles tests/filter_eval_test.c twice -- once
# plainly, once with -DLFU_KERNEL_TEST and tests/kstubs standing in for the
# four kernel headers, at -std=gnu89 because that is what a RHEL 9 kernel
# build uses -- runs both against xattr blobs written by tests/mkimage.sh's
# encoders, and requires (a) both outputs identical, (b) both equal to the
# expected list below.  A drift between the branches, or a decision that
# differs from the design's tables (docs/filter-levels.md §3, §4), fails.
#
# Usage: tests/filter_eval_test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- fixture bytes, from the same encoders the image builder uses ----------
# Extract the mk_* shell functions from mkimage.sh rather than run it: it
# needs mke2fs, and only the encoders are wanted here.
python3 - "$ROOT/tests/mkimage.sh" > "$WORK/encoders.sh" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
for name in ("mk_som", "mk_lov", "mk_lov_comp", "mk_lmv", "mk_linkea"):
    m = re.search(r'^%s\(\) \{\n.*?^\}\n' % name, s, re.S | re.M)
    if not m:
        sys.exit("encoder %s not found in mkimage.sh" % name)
    sys.stdout.write(m.group(0) + "\n")
PY
# shellcheck disable=SC1090
source "$WORK/encoders.sh"

mk_som     "$WORK/som.bin" 0x4 $((2 * 1024 * 1024 * 1024)) $((2 * 1024 * 1024 * 1024 / 512))
mk_lov     "$WORK/lov.bin" 0x1 1048576 - 3 7
mk_lov     "$WORK/lovrel.bin" $((0x1 | 0x80000000)) 1048576 - 1
mk_lov_comp "$WORK/lovcomp.bin" 1048576 "0x100:" "0x1:9"
mk_lmv     "$WORK/lmv.bin" 4 2
mk_linkea  "$WORK/link.bin" report_2026.csv second_link.txt

# --- two builds of one evaluator ------------------------------------------
CFLAGS="-O1 -g -Wall -Wextra -Wno-unused-parameter"
gcc $CFLAGS -std=gnu11 -I"$ROOT/src" \
	-o "$WORK/eval_user" "$ROOT/tests/filter_eval_test.c" \
	"$ROOT/src/lfu_filter_eval.c" || { echo "FAIL: userspace build"; exit 1; }
gcc $CFLAGS -std=gnu89 -Wdeclaration-after-statement -DLFU_KERNEL_TEST \
	-I"$ROOT/tests/kstubs" -I"$ROOT/src" \
	-o "$WORK/eval_kern" "$ROOT/tests/filter_eval_test.c" \
	"$ROOT/src/lfu_filter_eval.c" || { echo "FAIL: kernel-branch build"; exit 1; }

# The kernel branch of the EVALUATOR must not have picked up libc beyond the
# string functions the kernel also has (fnmatch is the glob stub's, and only
# the stub's).  Checked on the evaluator's own object, not the linked test
# binary, whose driver legitimately uses stdio.
gcc $CFLAGS -std=gnu89 -DLFU_KERNEL_TEST -I"$ROOT/tests/kstubs" -I"$ROOT/src" \
	-c -o "$WORK/eval_kern.o" "$ROOT/src/lfu_filter_eval.c" || exit 1
bad=$(nm -u "$WORK/eval_kern.o" 2>/dev/null | awk '{print $2}' |
      grep -vE '^(fnmatch|mem(cpy|cmp|set|chr|move)|str(len|cmp|ncmp|cpy|ncpy|chr)|__stack_chk_fail)$' || true)
if [ -n "$bad" ]; then
	echo "FAIL: kernel-branch evaluator references libc symbols: $bad"
	exit 1
fi

"$WORK/eval_user" "$WORK" > "$WORK/out_user.txt" || { echo "FAIL: userspace run"; exit 1; }
"$WORK/eval_kern" "$WORK" > "$WORK/out_kern.txt" || { echo "FAIL: kernel-branch run"; exit 1; }

# --- expected ---------------------------------------------------------------
cat > "$WORK/expected.txt" <<'EOF'
validate: empty filter                               ok
validate: n too large                                rejected
validate: bad field                                  rejected
validate: bad op                                     rejected
validate: unterminated pattern                       rejected
validate: list too long                              rejected
validate: dangling !                                 rejected
t0: --type d on a dir                                match
t0: --type d on a file                               nomatch
t0: --atime +1y, 400 days old                        match
t0: --atime +1y, 1 day old                           nomatch
t0: --projid 1999                                    match
t0: --attrs i on the immutable file                  match
t0: --attrs i on a plain file                        nomatch
t0: --attrs ^i on the immutable file                 nomatch
t0: --dev-blocks +1G on the striped inode            nomatch
t0: --perm /044 on 0600                              nomatch
t0: --perm /044 on 0644                              match
t0: ! --type f on a dir                              match
t1: --blocks +1G, striped with SOM 2G                match
t1: --blocks +1G, striped, no SOM                    unknown
t1: --blocks +1G, unstriped 200000B                  nomatch
t1: --size +100K, unstriped 200000B (i_size)         match
t1: --size +100K, striped SOM 2G                     match
t1: --size +100K, a 4096B dir                        nomatch
t1: --size +100K, released 123456B (MDT)             match
t1: --size 1M (0,1M] on 200000B                      match
t1: --stripe-count 2                                 match
t1: --stripe-count 2 on PFL (DoM+1)                  nomatch
t1: --stripe-count 1 on PFL (DoM+1)                  match
t1: --comp-count 2 on PFL                            match
t1: --layout mdt on PFL                              match
t1: --layout released                                match
t1: --layout released on striped                     nomatch
t1: --ost 7                                          match
t1: --ost 9                                          nomatch
t1: --pool fast on a v1 (no pool) layout             nomatch
t1: --stripe-size 1M                                 match
t1: --name report*                                   match
t1: --name second_link.txt (2nd entry)               match
t1: --name nosuch                                    nomatch
t1: --mdt-count 4                                    match
t1: --mdt-hash fnv_1a_64                             match
t1: stripes=2 (match) + size (unknown)               unknown
t1: stripes=3 (nomatch) + size (unknown)             nomatch
decode: striped                                      som=2147483648/4194304 stripes=2 ssize=1048576 lmv=4/2
decode: PFL                                          comps=2 mirrors=1 stripes=1 pattern=0x101
EOF

pass=1
if ! diff -u "$WORK/out_user.txt" "$WORK/out_kern.txt" > "$WORK/branch.diff"; then
	echo "FAIL: the two build branches disagree:"
	cat "$WORK/branch.diff"
	pass=0
fi
if ! diff -u "$WORK/expected.txt" "$WORK/out_user.txt" > "$WORK/expect.diff"; then
	echo "FAIL: evaluator output differs from expected:"
	cat "$WORK/expect.diff"
	pass=0
fi

n=$(wc -l < "$WORK/expected.txt")
if [ "$pass" = 1 ]; then
	echo "PASS ($n cases, identical on both branches)"
	exit 0
fi
echo "FAILED"
exit 1
