#!/bin/bash
# Both arms of the 160ac fix.
#
#   ARM=post     the tree as committed                   -> expect 160ac PASS
#   ARM=control  the stale-anchor refusal cut out of
#                liblustreapi_pfind.c, tests unchanged   -> expect 160ac FAIL
#   ARM=noglimpse  the --resolve glimpse cut out         -> expect 160ab FAIL
#
# The control is the point.  A test is verified by failing against the code it
# is meant to catch, not by passing beside the code it was written with --
# 68414's test_160za passed against the BROKEN module and had to be thrown
# away.  If ARM=control does not fail 160ac, the test is worthless however
# green ARM=post looks.
set -e
exec 9>/tmp/.lab160ac-arms.lock
flock -n 9 || { echo "another arm is running"; exit 1; }

L=${LTREE:-/home/nishida/lustre-160ac}
ARM=${ARM:?set ARM=post or ARM=control}
P=$L/lustre/utils/liblustreapi_pfind.c

cd $L
git checkout -- lustre/utils/liblustreapi_pfind.c

if [ "$ARM" = control ]; then
	python3 /home/nishida/cut-guard.py "$P"
elif [ "$ARM" = noglimpse ]; then
	python3 /home/nishida/cut-glimpse.py "$P"
else
	grep -q "sc.sc_startrec != 0 && oldest > sc.sc_startrec" $P ||
		{ echo "post arm is missing the guard in the source"; exit 1; }
	echo "post: guard present in source"
fi

echo "=== rebuilding utils"
make -j"$(nproc)" -C $L/lustre/utils >/tmp/arm-make.log 2>&1 ||
	{ echo BUILD FAILED; tail -20 /tmp/arm-make.log; exit 1; }
sudo make -C $L/lustre/utils install >/tmp/arm-install.log 2>&1 ||
	{ tail -10 /tmp/arm-install.log; exit 1; }
sudo ldconfig

# Guard against the trap that cost a day on 68414: the previous arm's build
# staying installed while the run reports on code that is not under test.
# Check the LIBRARY -- the guard lives in liblustreapi.so and /bin/lfs is byte
# identical between the arms, so checksumming the binary proves nothing -- and
# check for the refusal itself rather than a checksum, so the assertion says
# WHICH arm is loaded instead of merely that something changed.
LIB=$(find /usr/lib64 /usr/lib -name "liblustreapi.so.1.0.0" 2>/dev/null | head -1)
[ -n "$LIB" ] || { echo "cannot find the installed liblustreapi"; exit 1; }
n=$(strings "$LIB" | grep -c "has purged past the cookie" || true)
echo "  installed $LIB carries the refusal: $n"
# the glimpse is static and leaves no symbol, so the arm is asserted from the
# source it was built from rather than from the object
g=$(grep -c "NOGLIMPSE ARM" $P || true)   # 0 = glimpse live, 1 = disabled
echo "  built source has the glimpse DISABLED: $g"
if [ "$ARM" = control ] && [ "$n" != 0 ]; then
	echo "CONTROL ARM STILL HAS THE GUARD -- the run would prove nothing"; exit 1
fi
if [ "$ARM" = post ] && [ "$n" = 0 ]; then
	echo "POST ARM IS MISSING THE GUARD -- a stale control build is installed"; exit 1
fi
if [ "$ARM" = noglimpse ] && [ "$g" = 0 ]; then
	echo "NOGLIMPSE ARM STILL GLIMPSES -- the run would prove nothing"; exit 1
fi
if [ "$ARM" != noglimpse ] && [ "$g" != 0 ]; then
	echo "A NOGLIMPSE SOURCE IS STILL IN PLACE"; exit 1
fi

cd $L && git checkout -- lustre/utils/liblustreapi_pfind.c
echo "ARM-$ARM BUILT"
