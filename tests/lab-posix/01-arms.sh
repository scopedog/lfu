#!/bin/bash
# The POSIX case's two arms.
#
#   ARM=post   the tree as committed        -> llapi_scan_test -t 10 PASS
#   ARM=nofid  the lmd_fid clear cut out    -> FAIL, "carried a FID"
#   ARM=nostatx  the statx fallback replaced by lstat  -> sanity 157d FAIL
#
# Rebuilds lustre/utils and lustre/tests only: the fix is in liblustreapi and
# the case is in llapi_scan_test, so a full build is not needed for an arm.
set -e
exec 9>$HOME/.lab-posix.lock
flock -n 9 || { echo "another arm is running"; exit 1; }

L=${LTREE:-/home/nishida/lustre-160ac}
ARM=${ARM:?set ARM=post or ARM=nofid}
P=$L/lustre/utils/liblustreapi_pfind.c

cd $L
git checkout -- lustre/utils/liblustreapi_pfind.c

if [ "$ARM" = nofid ]; then
	python3 $HOME/cut-fid.py "$P"
elif [ "$ARM" = nostatx ]; then
	python3 $HOME/cut-statx.py "$P"
else
	grep -q "statx(AT_FDCWD, path, AT_SYMLINK_NOFOLLOW" $P ||
		{ echo "post arm is missing the statx fallback"; exit 1; }
	grep -q "No caller here has a FID to give" $P ||
		{ echo "post arm is missing the clear in the source"; exit 1; }
	echo "post: the clear is present in source"
fi

echo "=== rebuilding utils and tests"
make -j"$(nproc)" -C $L/lustre/utils >$HOME/posix-make.log 2>&1 ||
	{ echo BUILD FAILED; tail -20 $HOME/posix-make.log; exit 1; }
make -j"$(nproc)" -C $L/lustre/tests llapi_scan_test >>$HOME/posix-make.log 2>&1 ||
	{ echo TEST BUILD FAILED; tail -20 $HOME/posix-make.log; exit 1; }

# the test links liblustreapi -- see lab-scanstats/README: a rebuilt library is
# not enough if the binary was linked against the old one, so rebuild both and
# assert which arm the SOURCE that produced them carries
n=$(grep -c "NOFID ARM" $P || true)
x=$(grep -c "NOSTATX ARM" $P || true)
echo "  built source has the clear CUT: $n, statx CUT: $x"
if [ "$ARM" = nofid ] && [ "$n" = 0 ]; then
	echo "NOFID ARM STILL CLEARS -- the run would prove nothing"; exit 1
fi
if [ "$ARM" = post ] && [ "$n$x" != "00" ]; then
	echo "A CUT SOURCE IS STILL IN PLACE"; exit 1
fi
if [ "$ARM" = nostatx ] && [ "$x" = 0 ]; then
	echo "NOSTATX ARM STILL CALLS STATX -- the run would prove nothing"; exit 1
fi

cd $L && git checkout -- lustre/utils/liblustreapi_pfind.c
echo "ARM-$ARM BUILT"
