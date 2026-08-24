#!/bin/bash
# Stage 17: sanity before and after, over the tests that reach the code this
# series changes, plus an A/B of the descriptor behaviour LU-20624 fixes.
#
# Stage 10 compares 56* only, which is lfs find.  Round 8 rewrote
# cb_get_dirstripe()'s descriptor handling, and lfs getdirstripe and
# lfs getstripe -D reach that function too -- UPSTREAM commands this series
# does not otherwise touch.  A green 56* says nothing about them.
#
# Must run as root: llmount.sh insmods.  Needs uid 500 (RUNAS_ID) and an
# executable $HOME, or every non-root subtest fails execvp with EACCES.
set -e
BASE=$(cat /home/nishida/base.txt)
L=/home/nishida/lustre-release
T=$L/lustre/tests
export ONLY=${ONLY:-0e,17h,17i,27z,51c,51d,56,60h,65n,160d,162b,300}
export SLOW=yes
export HOME=/root
# llmount.sh mounts at /mnt/$FSNAME, NOT at the lab's own /mnt/testfs
FSNAME=${FSNAME:-lustre}
M=${MOUNT:-/mnt/$FSNAME}

id -u runas >/dev/null 2>&1 || useradd -u 500 -M runas
chmod o+x /home/nishida /home/nishida/lustre-release

# The lab's own testfs must be COMPLETELY gone before llmount.sh brings up its
# own.  A client left with a stale connection retries forever against an MDT
# that is no longer mounted -- "not available for connect ... (no target)" in
# dmesg -- and the first test needing an OST hangs rather than failing.
# Verify the module actually unloaded; do not assume.
teardown() {
	cd $T 2>/dev/null && ./llmountcleanup.sh > /dev/null 2>&1 || true
	umount -f $M 2>/dev/null || true
	umount /mnt/testfs 2>/dev/null || true
	umount /mnt/ost0 /mnt/ost1 /mnt/mdt0 2>/dev/null || true
	lustre_rmmod 2>/dev/null || true
}
teardown
if lsmod | grep -q "^lustre "; then
	echo "the lustre module is still loaded after rmmod:"; mount | grep lustre
	exit 1
fi

# The descriptor half of LU-20624, measured on BOTH builds.  "0 EBADF" only
# means something against the number the unpatched tree produces.
# MAIN PROCESS ONLY: strace -f under sudo attributes a shell's and its
# helpers' closes to the run, which is how the first write-up got "seven".
descriptor_probe() {   # $1 = label
	local out=/tmp/wprobe-$1
	command -v strace >/dev/null || { echo "  $1: probe SKIPPED, no strace"; return 0; }
	cd $T
	FORMAT=yes bash llmount.sh > /tmp/wpmount-$1.log 2>&1 || true
	if ! mountpoint -q $M; then
		echo "  $1: probe SKIPPED, llmount left no client mount at $M"
		tail -3 /tmp/wpmount-$1.log | sed 's/^/      /'
		./llmountcleanup.sh > /dev/null 2>&1 || true
		return 0
	fi
	mkdir -p $M/probe/tmpfs
	mountpoint -q $M/probe/tmpfs || mount -t tmpfs -o size=16m tmpfs $M/probe/tmpfs
	mkdir -p $M/probe/tmpfs/sub; touch $M/probe/tmpfs/a $M/probe/tmpfs/sub/b
	rm -rf $M/probe/foreign
	local HAVE_F=0
	lfs setdirstripe --foreign=none --xattr "lfu-r8" --flags 0xda05 \
		$M/probe/foreign > /dev/null 2>&1 && HAVE_F=1

	strace -e trace=close -o $out-gds.st \
		lfs getdirstripe -r $M/probe/tmpfs > /dev/null 2>&1 || true
	strace -e trace=close -o $out-find.st \
		lfs find $M/probe/tmpfs --printf "%p\n" > /dev/null 2>&1 || true
	echo "  $1: getdirstripe -r      EBADF=$(grep -c 'close(.*= -1 EBADF' $out-gds.st || true)"
	echo "  $1: lfs find --printf    EBADF=$(grep -c 'close(.*= -1 EBADF' $out-find.st || true)"
	if [ $HAVE_F -eq 1 ]; then
		strace -e trace=close -o $out-fgn.st \
			lfs find $M/probe --printf "%p\n" > $out-fgn.out 2>/dev/null || true
		echo "  $1: foreign walk         EBADF=$(grep -c 'close(.*= -1 EBADF' $out-fgn.st || true) paths=$(wc -l < $out-fgn.out)"
	else
		echo "  $1: foreign walk         no foreign dir on this build"
	fi
	umount $M/probe/tmpfs 2>/dev/null || true
	./llmountcleanup.sh > /dev/null 2>&1 || true
}

run_one() {   # $1 = label
	# ALWAYS before make install: it dies on a busy /sbin/mount.lustre
	# *after* a successful build, silently leaving the old modules in place
	teardown
	cd $L
	# autogen + configure per half, not once for the pair: this series adds
	# ZFS_SCAN_ENABLED as an AM_CONDITIONAL, so a tree configured before the
	# patches were applied fails the after build with "ZFS_SCAN_ENABLED does
	# not appear in AM_CONDITIONAL".  config.status is the honest witness
	# that configure ran -- lustre-release tracks a top-level Makefile.
	sh autogen.sh > /tmp/wautogen-$1.log 2>&1 || {
		echo "AUTOGEN $1 FAILED"; tail -10 /tmp/wautogen-$1.log; exit 1; }
	./configure --enable-server --enable-ldiskfs --disable-zfs \
		--with-linux="/usr/src/kernels/$(uname -r)" \
		> /tmp/wconf-$1.log 2>&1 || {
		echo "CONFIGURE $1 FAILED"; tail -20 /tmp/wconf-$1.log; exit 1; }
	grep -q "^ENABLE_LDISKFS='yes'" config.log || {
		echo "$1: ENABLE_LDISKFS is not yes"; exit 1; }
	test -f config.status || { echo "$1: no config.status"; exit 1; }
	make -j"$(nproc)" > /tmp/wmake-$1.log 2>&1 || {
		echo "BUILD $1 FAILED"; grep -nE 'error:' /tmp/wmake-$1.log | head; exit 1; }
	make install > /tmp/winst-$1.log 2>&1 || {
		echo "INSTALL $1 FAILED"; tail -8 /tmp/winst-$1.log; exit 1; }
	ldconfig; depmod -a

	cd $T
	./llmountcleanup.sh > /dev/null 2>&1 || true
	FORMAT=yes bash llmount.sh > /tmp/wllmount-$1.log 2>&1 || {
		echo "  $1: llmount failed"; tail -5 /tmp/wllmount-$1.log; }
	bash sanity.sh > /tmp/wsanity-$1.log 2>&1 || true
	./llmountcleanup.sh > /dev/null 2>&1 || true
	grep -E "^(PASS|FAIL|SKIP) " /tmp/wsanity-$1.log | awk '{print $1, $2}' | sort > /tmp/wres-$1.txt
	local n=$(wc -l < /tmp/wres-$1.txt)
	echo "  $1: $(grep -c ^PASS /tmp/wres-$1.txt) pass, $(grep -c ^FAIL /tmp/wres-$1.txt) fail, $(grep -c ^SKIP /tmp/wres-$1.txt) skip (total $n)"
	# a run that produced almost nothing compares equal to another that did
	# the same; assert the shape, not only that two sets agree
	if [ "$n" -lt 20 ]; then
		echo "  $1: ONLY $n RESULTS -- the run did not happen, not a pass"
		tail -20 /tmp/wsanity-$1.log | sed 's/^/    /'; exit 1
	fi
	descriptor_probe "$1"
}

echo "=== ONLY=$ONLY"
echo "=== BEFORE: $BASE"
cd $L && git reset -q --hard "$BASE"
run_one before

echo "=== AFTER: base + all nine patches"
cd $L && git am /home/nishida/0*.patch > /dev/null
git log --oneline "$BASE"..HEAD | wc -l
run_one after

echo "=== DIFF (before vs after)"
if diff /tmp/wres-before.txt /tmp/wres-after.txt; then echo "IDENTICAL"; else echo "DIFFERENT -- see above"; fi
echo "=== failures after, if any"
grep -E "^FAIL" /tmp/wres-after.txt || echo "  none"
echo "=== DESCRIPTOR A/B (the two runs' lines are above, in order)"
echo "STAGE17 DONE"
