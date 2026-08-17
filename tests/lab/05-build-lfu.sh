#!/bin/bash
# Stage 5: build the LFU kernel harnesses (lfu_ring carries the filter
# evaluator) and the userspace consumer.
set -e
echo "=== CONFIG_GLOB (glob_match, which --name/--pool need) ==="
grep -E '^CONFIG_GLOB' /boot/config-$(uname -r) || echo "CONFIG_GLOB not set!"

cd ~/lfu/src/kernel
make -C /lib/modules/$(uname -r)/build M=$PWD LUS=$HOME/lustre-release \
	KBUILD_EXTRA_SYMBOLS=$HOME/lustre-release/Module.symvers modules \
	> /tmp/kmod.log 2>&1 || { echo "MODULE BUILD FAILED"; grep -nE 'error:|Error [0-9]|warning:' /tmp/kmod.log | head -40; exit 1; }
echo "--- warnings, if any ---"
grep -nE 'warning:' /tmp/kmod.log | head -20 || echo "(none)"
ls -la *.ko

echo "=== the evaluator really is in lfu_ring.ko ==="
for s in lfu_filter_tier0 lfu_filter_tier1 lfu_ea_decode lfu_filter_validate; do
	if nm lfu_ring.ko | grep -qw "$s"; then echo "  present  $s"; else echo "  ABSENT   $s"; fi
done

echo "=== userspace consumer ==="
cd ~/lfu
make kmdt > /tmp/kmdt.log 2>&1 || { tail -20 /tmp/kmdt.log; exit 1; }
ls -la build/lfind-kmdt
# the ldiskfs device scanner too, for the cross-check against the same device
if make > /tmp/ldiskfs.log 2>&1; then
	echo "device scanner: built"; ls -la build/lfind-ldiskfs
else
	echo "device scanner: not built (needs libext2fs headers)"; tail -3 /tmp/ldiskfs.log
fi
echo "STAGE5 OK"
