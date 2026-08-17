#!/bin/bash
# Stage 5 (ZFS): the lfu_ring module and both userspace scanners.
set -e
echo "=== CONFIG_GLOB (glob_match, which --name/--pool need) ==="
grep -E '^CONFIG_GLOB' /boot/config-$(uname -r) || echo "CONFIG_GLOB not set!"

cd ~/lfu/src/kernel
make -C /lib/modules/$(uname -r)/build M=$PWD LUS=$HOME/lustre-release \
	KBUILD_EXTRA_SYMBOLS=$HOME/lustre-release/Module.symvers modules \
	> /tmp/kmod.log 2>&1 || { echo "MODULE BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/kmod.log | head -40; exit 1; }
grep -nE 'warning:' /tmp/kmod.log | head -10 || echo "(no warnings)"
ls -la lfu_ring.ko
for s in lfu_filter_tier0 lfu_filter_tier1 lfu_ea_decode lfu_filter_validate; do
	nm lfu_ring.ko | grep -qw "$s" && echo "  present  $s" || echo "  ABSENT   $s"
done

cd ~/lfu
make kmdt > /tmp/kmdt.log 2>&1 || { tail -20 /tmp/kmdt.log; exit 1; }
echo "kmdt: built"
ZVER=$(ls -d /usr/src/zfs-* | head -1)
make zfs ZFS_SRC="$ZVER" > /tmp/zfsbuild.log 2>&1 || { echo "ZFS SCANNER BUILD FAILED"; tail -25 /tmp/zfsbuild.log; exit 1; }
echo "lfind-zfs: built against $ZVER"
make front > /dev/null 2>&1 && echo "lfind: built"
ls -la build/
echo "STAGE5 OK"
