#!/bin/bash
# 68159 ccbe7b56 -- --links drops a foreign directory on a device scan.
#
# struct lmv_foreign_md's lfm_length sits at the same offset as
# lmv_user_md_v1's lum_stripe_count, so find_decide()'s nlink gate reads a
# foreign LMV's value length as a stripe count and asks for a stat.  A walk
# has a path and answers correctly, paying one pointless stat; a device scan
# has neither path nor descriptor, so the object goes undecided and is
# dropped -- out of BOTH --links N and ! --links N.
#
# Run as root, with the filesystem UNMOUNTED and the fixture already on the
# MDT device (see the header of the round doc).  Point DEV at the MDT.
#
#   MTREE=~/lustre-spgot DEV=/tmp/lustre-mdt1 bash 09-arms-foreign-links.sh
#
# Against an UNFIXED build B is {plain} and D is {fgn,f0}: the two foreign
# directories are in neither, which is what makes this a drop and not a
# disagreement about the answer.
set -u
T=${MTREE:-/home/nishida/lustre-spgot}
DEV=${DEV:-/tmp/lustre-mdt1}
L=$T/lustre/utils/.libs
export LD_LIBRARY_PATH=$L:$T/lnet/utils/lnetconfig/.libs:$T/libcfs/libcfs/.libs:$T/lnet/utils/.libs
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; echo "        got: $2"; fail=$((fail+1)); }

mount -t lustre | grep -q . && { echo "unmount the filesystem first"; exit 1; }
[ -e "$DEV" ] || { echo "no such device: $DEV"; exit 1; }

scan() { $L/lfind --device "$DEV" --paths "$@" 2>&1 | grep '^/fgn' | sort | tr '\n' ' '; }

A=$(scan)
B=$(scan --links 2)
C=$(scan --links 5)
D=$(scan ! --links 2)

########## the fixture is what the arms below assume
[ "$A" = "/fgn /fgn/f0 /fgn/fdir /fgn/fdir2 /fgn/plain " ] &&
	ok "the scan sees all five objects without --links" ||
	bad "fixture is not the one these arms were written for" "$A"

########## the defect: a foreign directory answers --links like any other
[ "$B" = "/fgn/fdir /fgn/fdir2 /fgn/plain " ] &&
	ok "--links 2 answers both foreign dirs and the plain one" ||
	bad "--links 2 did not answer the foreign dirs" "$B"

########## and the gate still gates what it was written for
[ "$C" = "/fgn " ] &&
	ok "--links 5 answers only the parent" ||
	bad "--links 5" "$C"

########## the two answers must partition A -- an undecided object is in
########## neither, which is how the defect showed itself
[ "$D" = "/fgn /fgn/f0 " ] &&
	ok "! --links 2 answers exactly the rest" ||
	bad "! --links 2" "$D"

both=$(printf '%s%s' "$B" "$D" | tr ' ' '\n' | grep -c '^/fgn')
[ "$both" = 5 ] &&
	ok "--links 2 and its negation partition the five objects" ||
	bad "the two answers do not add up to the five objects" "$both of 5"

echo "=== $pass pass, $fail fail"
exit $((fail > 0))
