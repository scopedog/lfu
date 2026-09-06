#!/bin/bash
# Round 21's regression arms: the seven fixes the 68419/68420 reviews drew,
# which round 21 fixed locally and which had never run against a real mount.
#
# Four are discriminators -- they FAIL on the pushed PS9 build and pass on
# the fixed one.  The timestamp arm documents behaviour the man page fix
# claims and passes on both; it is a control on the page, not on the code.
#
# The discriminating artifact is liblustreapi.so, not lfs: find_cookie_read(),
# find_cookie_check() and find_ck_escape() all live in the library.
set -u
M=${M:-/mnt/lustre}
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; echo "        ${2//$'\n'/$'\n'        }"; fail=$((fail+1)); }

mount -t lustre | grep -q "on $M " || { echo "$M is not mounted"; exit 1; }
echo "=== lfs:  $(lfs --version 2>&1 | head -1)"
echo "=== lib:  $(ls -l --time-style=+%F_%T $(ldd $(command -v lfs) | awk '/liblustreapi/{print $3}') | awk '{print $6, $7}')"

########## 2926fe9e -- a search root holding a newline
# Only '/' and NUL are excluded from a name.  Written raw the root ended the
# header line, so it read back short and every run after the first was
# refused naming a path the caller never gave -- the space case one
# character further out.
echo "=== a search root with a newline"
D=$(printf '%s/lab\nnl' "$M")
rm -rf "$D"; lfs mkdir -i 0 "$D" 2>/dev/null || mkdir -p "$D" || exit 1
touch "$D/f"; sync; sleep 1
CK=/tmp/r21.nl.ck; rm -f $CK

out=$(lfs find "$D" --since-cookie $CK -type f 2>&1); rc=$?
if (( rc != 0 )); then
	bad "the first run under a newline root failed (rc=$rc)" "$out"
else
	ok "the first run under a newline root writes the cookie"
	# the header must be one line: a raw newline splits it in two
	n=$(wc -l < $CK)
	hdr=$(head -1 $CK)
	grep -qF 'lab\nnl' <<<"$hdr" &&
		ok "the header carries the root escaped, on one line" ||
		bad "the header did not escape the newline" "$hdr ($n lines)"

	out=$(lfs find "$D" --since-cookie $CK -type f 2>&1); rc=$?
	(( rc == 0 )) && ok "the second run reads its own cookie back" ||
		bad "the second run refused its own cookie (rc=$rc)" "$out"
fi

# a backslash root, which is what makes the escape injective
echo "=== a search root with a backslash"
B="$M/lab\\bs"
rm -rf "$B"; lfs mkdir -i 0 "$B" 2>/dev/null || mkdir -p "$B" || exit 1
touch "$B/f"; sync; sleep 1
CK=/tmp/r21.bs.ck; rm -f $CK
lfs find "$B" --since-cookie $CK -type f >/dev/null 2>&1
out=$(lfs find "$B" --since-cookie $CK -type f 2>&1); rc=$?
(( rc == 0 )) && ok "a backslash root reads its own cookie back" ||
	bad "a backslash root refused its own cookie (rc=$rc)" "$out"

########## d1c134a5 -- the silent refusals now speak
echo "=== an empty cookie name is named as the argument at fault"
out=$(lfs find "$M" --since-cookie "" -type f 2>&1)
grep -q 'since-cookie needs the name of a file' <<<"$out" &&
	ok "the empty cookie name is refused with a message naming it" ||
	bad "the empty cookie name was refused silently" "$out"

echo "=== a cookie name too long to write beside"
# The window is narrow and needs a DEEP path, not one long component:
# find_cookie_read() runs first and its fopen() refuses a component over
# NAME_MAX, so a single 4090-char name never reaches find_cookie_check().
# What reaches it is a path of 4092..4095 whose components all fit -- long
# enough that "%s.new" overflows PATH_MAX, short enough that fopen() gets
# to ENOENT and treats it as the first run.
DEEP=/tmp/r21deep; rm -rf $DEEP; P=$DEEP; mkdir -p $P
SEG=$(printf 'd%.0s' $(seq 1 250))
for i in $(seq 1 16); do P=$P/$SEG; mkdir -p "$P" 2>/dev/null || break; done
CKL="$P/$(printf 'c%.0s' $(seq 1 $((4093 - ${#P} - 1))))"
if (( ${#CKL} < 4092 || ${#CKL} > 4095 )); then
	echo "  SKIP  could not build a cookie path in the 4092..4095 window (${#CKL})"
else
	out=$(lfs find "$M" --since-cookie "$CKL" -type f 2>&1)
	grep -q 'too long to write beside' <<<"$out" &&
		ok "an over-long cookie name is refused with a message (len ${#CKL})" ||
		bad "an over-long cookie name was refused silently" "$(sed 's|/tmp/r21deep[^ ]*|<LONGPATH>|' <<<"$out" | head -2)"
fi

########## 797f62e9 -- the refusal names both anchored spellings
# NOT via lfs find.  lfs_find_parse() carries a guard with the IDENTICAL
# condition and refuses first, with its own message naming --changelog, so
# neither lfs nor lfind can reach the library's line.  The reachable caller
# is a program calling llapi_find_since() directly, which is what
# resolve_guard is.  The review's stated repro was the command line.
echo "=== --resolve without --changelog names both anchored options"
if [ -x /tmp/resolve_guard ]; then
	out=$(/tmp/resolve_guard "$M" /tmp/r21.nl.ck 2>&1)
	if grep -q -- '--since and --since-cookie already read the object' <<<"$out"; then
		ok "the library refusal names --since-cookie as well as --since"
	else
		bad "the library refusal still names only --since" "$out"
	fi
else
	echo "  SKIP  resolve_guard not built"
fi

# and the command line is refused by the parser, on both builds
out=$(lfs find "$M" --since-cookie /tmp/r21.nl.ck --resolve -type f 2>&1)
grep -q -- 'it needs --changelog' <<<"$out" &&
	ok "the command line is refused first by the shared parser" ||
	bad "the parser guard did not fire" "$out"

########## 3eb08208 -- one refusal, reported once
# find_cookie_read() names the reason for both of its -EINVAL returns; the
# caller then added "cannot read", and the file read fine.
echo "=== a cookie refused for its root is reported once"
CK=/tmp/r21.nl.ck
O="$M/r21other"; rm -rf "$O"; lfs mkdir -i 0 "$O" 2>/dev/null || mkdir -p "$O"
out=$(lfs find "$O" --since-cookie $CK -type f 2>&1)
n=$(grep -c 'cannot read' <<<"$out")
if (( n == 0 )); then
	ok "the wrong-root refusal is reported once, by the reason"
else
	bad "the wrong-root refusal is still reported twice" "$out"
fi

########## 2a56e006 -- the eight spellings the page now lists
# set_since()'s table, which lfs-find.1 listed two of.  Passes on both
# builds: this is the man page being checked against the code.
echo "=== every timestamp spelling lfs-find.1 now lists is accepted"
NOW=$(date +%s)
for s in "@$NOW" "2026-08-25T18:00:00" "2026-08-25 18:00:00" \
	 "2026-08-25T18:00" "2026-08-25 18:00" "2026-08-25" \
	 "18:00:00" "18:00"; do
	out=$(lfs find "$M" --since "$s" -type f 2>&1); rc=$?
	if (( rc == 0 )) && ! grep -qi 'bad time\|invalid\|cannot parse' <<<"$out"; then
		ok "--since '$s' is accepted"
	else
		bad "--since '$s' was refused (rc=$rc)" "$out"
	fi
done

echo "=== r21 arms: $pass passed, $fail failed"
exit $(( fail > 0 ))
