#!/bin/bash
# Stage 7: sanity.sh 56* -- the lfs find tests -- before and after, on the
# same box.  "Before" is the base commit, "after" is base + both patches;
# the acceptance criterion for LU-20605 is that the two pass/fail sets are
# identical (and green).  Two builds, two runs, one diff.
#
# Must run as root: llmount.sh insmods.  Needs uid 500 (RUNAS_ID) and an
# executable $HOME, or every non-root subtest fails execvp with EACCES.
# The lab's own MGS+MDT+OST must be unmounted first, or llmount's MGS
# collides with it.
set -e
# absolute paths throughout: this runs under sudo, where ~ is /root
BASE=$(cat /home/nishida/base.txt)
L=/home/nishida/lustre-release
export ONLY=56
export SLOW=yes
export HOME=/root
id -u runas >/dev/null 2>&1 || useradd -u 500 -M runas
chmod o+x /home/nishida /home/nishida/lustre-release

umount /mnt/testfs 2>/dev/null || true
umount /mnt/ost0 2>/dev/null || true
umount /mnt/mdt0 2>/dev/null || true
lustre_rmmod 2>/dev/null || true

run_one() {   # $1 = label
	cd $L
	make -j"$(nproc)" > /tmp/make-$1.log 2>&1 || { echo "BUILD $1 FAILED"; grep -nE 'error:' /tmp/make-$1.log | head; exit 1; }
	make install > /tmp/inst-$1.log 2>&1 || { tail -5 /tmp/inst-$1.log; exit 1; }
	ldconfig; depmod -a
	nm -D --defined-only /usr/lib64/liblustreapi.so.1.0.0 2>/dev/null | grep -c llapi_scan_namespace | sed "s/^/  $1: llapi_scan_namespace symbols installed = /"
	cd $L/lustre/tests
	./llmountcleanup.sh > /dev/null 2>&1 || true
	# sanity.sh expects the fs already up; llmount.sh formats the
	# /tmp/lustre-* loop images and mounts them (FORMAT is not implicit)
	FORMAT=yes bash llmount.sh > /tmp/llmount-$1.log 2>&1 || {
		echo "  $1: llmount failed"; tail -5 /tmp/llmount-$1.log; }
	bash sanity.sh > /tmp/sanity56-$1.log 2>&1 || true
	./llmountcleanup.sh > /dev/null 2>&1 || true
	grep -E "^(PASS|FAIL|SKIP) " /tmp/sanity56-$1.log | awk '{print $1, $2}' | sort > /tmp/res-$1.txt
	echo "  $1: $(grep -c ^PASS /tmp/res-$1.txt) pass, $(grep -c ^FAIL /tmp/res-$1.txt) fail, $(grep -c ^SKIP /tmp/res-$1.txt) skip"
}

echo "=== BEFORE: $BASE"
cd $L && git reset -q --hard "$BASE"
run_one before

echo "=== AFTER: base + LU-20603 + LU-20605"
cd $L && git am /home/nishida/0001-*.patch /home/nishida/0002-*.patch > /dev/null && git log --oneline -3
run_one after

echo "=== DIFF (before vs after)"
if diff /tmp/res-before.txt /tmp/res-after.txt; then
	echo "IDENTICAL"
else
	echo "DIFFERENT"
fi
echo "=== failures after, if any"
grep -E "^FAIL" /tmp/res-after.txt || echo "  none"
echo "STAGE7 DONE"
