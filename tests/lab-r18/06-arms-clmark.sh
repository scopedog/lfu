#!/bin/bash
# Round 19's arms for the two 68418 defects lreview found, plus the ordering
# constraint the rebase turned up.
#
#   a CL_MARK is not an object.  mdd_changelog_write_header() writes the
#   marker flags into the union with cr_tfid, so cr_tfid.f_seq reads back as
#   CLM_ON|CLM_START = 0x10001 -- and fid_seq_is_igif() accepts anything in
#   [12, 0xffffffff], so the FID gate passed a value that is not a FID and
#   "lfs find --changelog all" printed [0x10001:0x0:0x0].
#
#   -printf's widening has to reach --since: find_want() clears
#   LLAPI_SCAN_PROJID and find_decide() gates find_get_projid() on
#   fc_gather_all, so with the flag unset %LP answered DEFAULT_PROJID.
#
#   and the CL_MARK drop has to sit BELOW the cookie's anchor update, or a
#   trailing mark stops advancing the anchor -- which is the bug 68419's own
#   comment says it fixed by putting that update above the FID test.
set -u
L=${LTREE:-/home/nishida/lustre-r18}
M=${M:-/mnt/lustre}
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; echo "        $2"; fail=$((fail+1)); }

mount -t lustre | grep -q "on $M " || { echo "$M is not mounted"; exit 1; }
MDT=$(lctl dl | awk '/ mdt /{print $4}' | sort | head -1)
[ -n "$MDT" ] || { echo "no MDT is up"; exit 1; }
echo "=== lfs: $(lfs --version 2>&1 | head -1)  MDT: $MDT"

D=$M/r19mark; rm -rf $D
lfs mkdir -i 0 $D || exit 1
CL=$(lctl --device $MDT changelog_register -n 2>/dev/null)
[ -n "$CL" ] || { echo "no changelog user could be registered"; exit 1; }
lctl set_param -n mdd.*.changelog_mask=ALL >/dev/null 2>&1 || true
echo "=== changelog user: $CL"

touch $D/f1 $D/f2; sync; sleep 2

########## a CL_MARK is not printed as an object -- and cannot be reached
#
# CHANGELOG_MINMASK is BIT(CL_MARK), and mdd_changelog_mask_seq_write() passes
# it to cfs_str2mask() as the floor, so CL_MARK can never be masked out.
# mdd_changelog_write_header() returns early whenever CL_MARK is in the
# current mask, so no CL_MARK record is ever written to the log.  The guard in
# find_since_cand_cb() is therefore correct and unreachable on this build, and
# this arm cannot discriminate: it is reported as a SKIP rather than left as a
# green line that proves nothing.  Measured 2026-09-03 -- asking for
# "creat mkdir" gives "MARK CREAT MKDIR", and deregistering every user and
# re-registering produced an empty log.
echo "=== 68418 a CL_MARK is not delivered as an object"
marks=$(lfs changelog $MDT 2>/dev/null | grep -c "MARK" || true)
out=$(lfs find $M --changelog all 2>&1)
echo "        MARK records in the log: $marks"
if (( marks == 0 )); then
	echo "  SKIP  no CL_MARK can reach the log: MARK is the minimum mask"
	# what the arm CAN still assert: the guard took nothing else
	if grep -q "/f1$" <<<"$out" && grep -q "/f2$" <<<"$out"; then
		ok "the objects the log named are still delivered"
	else
		bad "the guard dropped real objects" "$(head -4 <<<"$out")"
	fi
else
	if grep -qE '^\[0x1000?1:0x0:0x0\]' <<<"$out"; then
		bad "a marker's flags were printed as a FID" "$(grep -E '^\[0x' <<<"$out" | head -2)"
	else
		ok "no marker flags printed as a FID"
	fi
fi

########## -printf %LP under --since answers the real projid
echo "=== 68418 -printf %LP under --since"
# a non-zero project id: with DEFAULT_PROJID being 0, "0 == 0" would pass on
# the unfixed library too
lfs project -p 4242 -r -s $D >/dev/null 2>&1 || true
touch $D/p1; sync; sleep 1
want=$(lfs project -d $D 2>/dev/null | awk '{print $1}')
echo "        project id set on $D: ${want:-<none>}"
[ "${want:-0}" != "0" ] ||
	echo "  NOTE  the project id is 0, so this arm cannot discriminate"
# stdout only: --since writes its closing counts to stderr, and folding them
# in made the comparison fail on the warning text rather than on the projid
walk=$(lfs find $D -type f -printf '%LP\n' 2>/dev/null | sort -u | tr '\n' ' ')
since=$(lfs find $D --since 1h -type f -printf '%LP\n' 2>/dev/null |
	sort -u | tr '\n' ' ')
echo "        walk: '$walk'   --since: '$since'"
if [ "$walk" = "$since" ]; then
	ok "--since -printf %LP agrees with a plain walk"
else
	bad "--since -printf %LP disagrees with a walk" "walk='$walk' since='$since'"
fi

########## a trailing mark must not stop the cookie's anchor advancing
# Only meaningful where a mark can be written, which is nowhere on this build
# (see above).  Kept because the ordering it guards is real -- the CL_MARK
# guard sits below the anchor update for exactly this reason -- and because a
# server whose mask could drop MARK would need it.
echo "=== 68419 the anchor still advances over a trailing mark"
CK=/tmp/r19.mark.ck; rm -f $CK
lfs find $D --since-cookie $CK -type f >/dev/null 2>&1
a1=$(awk -v m="$MDT" '$1==m {print $2}' $CK 2>/dev/null)
# turn the log off and on again: that writes marks at the end of it
lctl set_param -n mdd.*.changelog_mask="MARK" >/dev/null 2>&1 || true
lctl set_param -n mdd.*.changelog_mask=ALL >/dev/null 2>&1 || true
sync; sleep 2
lfs find $D --since-cookie $CK -type f >/dev/null 2>&1
a2=$(awk -v m="$MDT" '$1==m {print $2}' $CK 2>/dev/null)
echo "        anchor: $a1 -> $a2"
if [ -n "$a1" ] && [ -n "$a2" ] && (( a2 >= a1 )); then
	ok "the anchor did not go backwards over the marks"
else
	bad "the anchor stalled or vanished" "before=$a1 after=$a2"
fi

echo "=== clmark arms: $pass passed, $fail failed"
exit $(( fail > 0 ))
