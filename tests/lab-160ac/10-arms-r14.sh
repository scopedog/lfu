#!/bin/bash
# Round 14's arms: the two 160ac cases added for 68419's cookie parse.
#
#   ARM=post      the tree as committed                 -> 160ac PASS
#   ARM=nobound   the signed bound test put back        -> 160ac FAIL (the
#                 negative-index line is stored ~32GB past the array)
#   ARM=noheader  the foreign-cookie refusal cut out    -> 160ac FAIL
#
# A new case is verified by failing against the code it is meant to catch.  If
# an arm passes, the case is worthless however green the post arm looks.
set -e
exec 9>$HOME/.lab160ac-arms.lock
flock -n 9 || { echo "another arm is running"; exit 1; }

L=${LTREE:-/home/nishida/lustre-160ac}
ARM=${ARM:?set ARM=post, nobound or noheader}
P=$L/lustre/utils/liblustreapi_pfind.c

cd $L
git checkout -- lustre/utils/liblustreapi_pfind.c

case "$ARM" in
nobound)  python3 /home/nishida/cut-bound.py "$P" ;;
noheader) python3 /home/nishida/cut-header.py "$P" ;;
post)
	grep -q 'mdt >= (unsigned int)nstarts' $P ||
		{ echo "post arm is missing the unsigned bound"; exit 1; }
	grep -q "is a cookie for" $P ||
		{ echo "post arm is missing the header refusal"; exit 1; }
	echo "post: both guards present in source" ;;
*) echo "unknown ARM=$ARM"; exit 1 ;;
esac

echo "=== rebuilding utils"
make -j"$(nproc)" -C $L/lustre/utils >$HOME/arm-make.log 2>&1 ||
	{ echo BUILD FAILED; tail -20 $HOME/arm-make.log; exit 1; }
sudo make -C $L/lustre/utils install >$HOME/arm-install.log 2>&1 ||
	{ tail -10 $HOME/arm-install.log; exit 1; }
sudo ldconfig

# Assert WHICH arm is installed, not merely that something changed: the guards
# live in liblustreapi.so and /bin/lfs is identical between the arms.  The
# header refusal carries a string, so the object answers for it; the bound test
# does not, so that arm is asserted from the source it was built from.
LIB=$(find /usr/lib64 /usr/lib -name "liblustreapi.so.1.0.0" 2>/dev/null | head -1)
[ -n "$LIB" ] || { echo "cannot find the installed liblustreapi"; exit 1; }
h=$(strings "$LIB" | grep -c "is a cookie for" || true)
b=$(grep -c "NOBOUND ARM" $P || true)
echo "  installed $LIB carries the header refusal: $h"
echo "  built source has the signed bound back: $b"
case "$ARM" in
post)     [ "$h" != 0 ] && [ "$b" = 0 ] || { echo "STALE BUILD -- post arm is not what is installed"; exit 1; } ;;
noheader) [ "$h" = 0 ] || { echo "NOHEADER ARM STILL REFUSES -- the run would prove nothing"; exit 1; } ;;
nobound)  [ "$b" != 0 ] && [ "$h" != 0 ] || { echo "NOBOUND ARM IS NOT WHAT IS INSTALLED"; exit 1; } ;;
esac

cd $L && git checkout -- lustre/utils/liblustreapi_pfind.c
echo "ARM-$ARM BUILT"
