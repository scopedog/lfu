#!/bin/bash
# Round 19's regression arms: the two cookie-parsing bugs lreview found on
# 68419, both of which the round-18 arms passed straight through.
#
# The round-18 arms exercised the cookie's root binding and reported PASS --
# every path they used was space-free, and every cookie they read was one
# lfs had just written.  Neither bug is reachable from a fixture that only
# uses well-formed input, which is the point of these two.
set -u
L=${LTREE:-/home/nishida/lustre-r18}
M=${M:-/mnt/lustre}
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail+1)); }

mount -t lustre | grep -q "on $M " || { echo "$M is not mounted"; exit 1; }
echo "=== lfs: $(lfs --version 2>&1 | head -1)"
MDT=$(lctl dl | awk '/ mdt /{print $4}' | sort | head -1)
[ -n "$MDT" ] || { echo "no MDT is up"; exit 1; }

########## a search root that contains a space
# %s in the header parse cut the root at the first space, so the root
# comparison failed against a truncated path and refused every run after the
# first -- naming a path the caller never gave.  The root is whatever
# realpath() returned, so one directory with a space in it was enough.
echo "=== a search root with a space"
D="$M/lab space dir"
rm -rf "$D"; lfs mkdir -i 0 "$D" 2>/dev/null || mkdir -p "$D" || exit 1
touch "$D/f"; sync; sleep 1
CK=/tmp/r19.space.ck; rm -f $CK

out=$(lfs find "$D" --since-cookie $CK -type f 2>&1); rc=$?
if (( rc != 0 )); then
	bad "the first run under a spaced root failed (rc=$rc)" "$out"
else
	ok "the first run under a spaced root writes the cookie"
	hdr=$(head -1 $CK)
	grep -qF "under $D" <<<"$hdr" &&
		ok "the header records the root whole" ||
		bad "the header truncated the root" "$hdr"

	out=$(lfs find "$D" --since-cookie $CK -type f 2>&1); rc=$?
	(( rc == 0 )) && ok "the second run reads its own cookie back" ||
		bad "the second run refused its own cookie (rc=$rc)" "$out"

	# and the binding still means something with a space on both sides
	O="$M/other space dir"
	rm -rf "$O"; lfs mkdir -i 0 "$O" 2>/dev/null || mkdir -p "$O"
	out=$(lfs find "$O" --since-cookie $CK -type f 2>&1); rc=$?
	if (( rc != 0 )) && grep -qF "under '$D'" <<<"$out"; then
		ok "a different spaced root is refused, and named in full"
	else
		bad "a different spaced root was not refused in full (rc=$rc)" "$out"
	fi
fi

########## an MDT name that is not the four hex digits the writer emits
# %4x converts the leading digits and ignores the rest, so both of these
# anchored MDT0000 at an index never written for it -- and an anchor past the
# end of the log suppresses the whole answer at exit 0, which is the short
# answer with nothing said that the stale check exists to catch.
echo "=== a malformed MDT name in the cookie"
E="$M/r19mdt"
rm -rf "$E"; lfs mkdir -i 0 "$E" || exit 1
lctl --device $MDT changelog_register -n >/dev/null 2>&1
lctl set_param -n mdd.*.changelog_mask=ALL >/dev/null 2>&1 || true
touch "$E/f"; sync; sleep 2
CK=/tmp/r19.mdt.ck

for bad_name in "${MDT}_UUID" "${MDT}1" "${MDT%0}-1"; do
	printf '# lfs find --since-cookie for %s under %s\n%s 999999\n' \
		"${MDT%%-MDT*}" "$E" "$bad_name" > $CK
	out=$(lfs find "$E" --changelog $MDT --resolve --since-cookie $CK \
		-type f 2>&1)
	if [ -n "$out" ]; then
		ok "'$bad_name' is ignored rather than read as an anchor"
	else
		bad "'$bad_name' was honoured as an MDT0000 anchor" "empty answer, exit 0"
	fi
done

# the writer's own form still anchors, or the check above proves nothing
printf '# lfs find --since-cookie for %s under %s\n%s 999999\n' \
	"${MDT%%-MDT*}" "$E" "$MDT" > $CK
out=$(lfs find "$E" --changelog $MDT --resolve --since-cookie $CK -type f 2>&1)
[ -z "$out" ] && ok "the writer's own MDT name still anchors" ||
	bad "a well-formed anchor was ignored too" "$out"

echo "=== cookie arms: $pass passed, $fail failed"
exit $(( fail > 0 ))
