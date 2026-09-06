#!/bin/bash
# -name against a start point the caller spelled with a trailing slash.
#
# sr_name points INTO the walked path, so for "/mnt/lustre/d/" the basename
# is not a suffix of the string and no pointer into it spells "d".
# llapi_scan_namespace() and llapi_scan_fid() trim their path argument for
# that reason; llapi_find() did not, and -name silently stopped matching.
#
# Run with LFS=<path to a stock lfs> to see the arms fail: stock matches
# nothing at all for these start points, its fname being "".
set -u
M=${M:-/mnt/lustre}
LFS=${LFS:-lfs}
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail+1)); }

mount -t lustre | grep -q "on $M " || { echo "$M is not mounted"; exit 1; }
echo "=== lfs: $($LFS --version 2>&1 | head -1)"

D=$M/slashdir
rm -rf "$D"; lfs mkdir -i 0 "$D" 2>/dev/null || mkdir -p "$D" || exit 1
mkdir -p "$D/sub"; touch "$D/a" "$D/sub/b"

########## -name tests the basename, whatever the start point's spelling
for sp in "$D" "$D/" "$D///"; do
	out=$($LFS find "$sp" -maxdepth 0 --name slashdir 2>&1)
	[ -n "$out" ] && ok "--name slashdir matches '$sp'" ||
		bad "--name slashdir did not match '$sp'" "${out:-<no output>}"

	out=$($LFS find "$sp" -maxdepth 0 --name '*slashdir*' 2>&1)
	[ -n "$out" ] && ok "--name '*slashdir*' matches '$sp'" ||
		bad "--name '*slashdir*' did not match '$sp'" "${out:-<no output>}"

	# the slash is not part of the name, so a pattern ending in one must not
	out=$($LFS find "$sp" -maxdepth 0 --name '*/' 2>&1)
	[ -z "$out" ] && ok "--name '*/' matches nothing for '$sp'" ||
		bad "--name '*/' matched '$sp'" "$out"
done

########## and the walk composes children without a doubled separator
for sp in "$D/" "$D///"; do
	out=$($LFS find "$sp" 2>&1 | grep -F "$D//" )
	[ -z "$out" ] && ok "no doubled separator below '$sp'" ||
		bad "doubled separator below '$sp'" "$(head -2 <<<"$out")"
done

########## "/" is its own name and keeps its slash -- basename(3) says so
out=$($LFS find / -maxdepth 0 --name / 2>&1)
[ -n "$out" ] && ok "--name / matches the root" ||
	bad "--name / did not match the root" "${out:-<no output>}"

########## control: a spelling with no trailing slash is unchanged, and
########## agrees with find(1).  This arm passes on stock too.
g=$(find "$D" -maxdepth 1 2>/dev/null | sort)
l=$($LFS find "$D" -maxdepth 1 2>&1 | sort)
[ "$g" = "$l" ] && ok "control: '$D' agrees with find(1)" ||
	bad "control: '$D' differs from find(1)" "$(diff <(echo "$g") <(echo "$l") | head -4)"

echo "=== slash arms: $pass passed, $fail failed"
exit $(( fail > 0 ))
