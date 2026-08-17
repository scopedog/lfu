#!/bin/bash
# Stage 8: Option 2 (kernel, filter pushed down) against Option 1 (userspace
# device scanner, same filter, same device, read-only while mounted).  The FID
# sets must agree -- that is the only check that says the kernel evaluator and
# the userspace one answer the same question.
cd ~/lfu
kscan() {
	sudo rmmod lfu_ring 2>/dev/null
	sudo insmod src/kernel/lfu_ring.ko dev=testfs-MDT0000-osd 2>/dev/null
	sudo timeout 180 build/lfu-scan-kmdt "$@" /dev/lfu_scan 2>/dev/null |
		grep -oE '^\[0x[0-9a-f]+:0x[0-9a-f]+:0x[0-9a-f]+\]' | sort
}
dscan() {
	sudo timeout 300 build/lfu-scan-ldiskfs "$@" /lustre/mdt.img 2>/dev/null |
		grep -oE '^\[0x[0-9a-f]+:0x[0-9a-f]+:0x[0-9a-f]+\]' | sort
}
cmp_one() {
	local label="$1"; shift
	local a b
	a=$(kscan "$@"); b=$(dscan "$@")
	local na=$(echo "$a" | grep -c . ) nb=$(echo "$b" | grep -c .)
	if [ "$a" = "$b" ]; then
		printf '%-40s AGREE  (%s objects)\n' "$label" "$na"
	else
		printf '%-40s DIFFER kernel=%s device=%s\n' "$label" "$na" "$nb"
		diff <(echo "$a") <(echo "$b") | head -8
	fi
}

echo "=== the same filter through both scanners ==="
cmp_one "--blocks +1G"          --blocks +1G
cmp_one "--size +1G"            --size +1G
cmp_one "--stripe-count 4"      --stripe-count 4
cmp_one "--pool fast"           --pool fast
cmp_one "--projid 1999"         --projid 1999
cmp_one "--attrs i"             --attrs i
cmp_one "--layout mdt"          --layout mdt
cmp_one "--name report*"        --name 'report*'
cmp_one "--name second_link.txt" --name second_link.txt
cmp_one "--comp-count +1"       --comp-count +1
cmp_one "--type d"              --type d
cmp_one "--dev-blocks +1G"      --dev-blocks +1G

echo
echo "=== what --blocks +1G actually found, in full ==="
sudo rmmod lfu_ring 2>/dev/null
sudo insmod src/kernel/lfu_ring.ko dev=testfs-MDT0000-osd
sudo timeout 180 build/lfu-scan-kmdt --blocks +1G /dev/lfu_scan 2>/dev/null
echo
echo "=== and the same object from the client, for the size ==="
sudo lfs getstripe -c /mnt/testfs/shapes/big1 2>/dev/null | tail -1
sudo stat -c 'size=%s blocks=%b' /mnt/testfs/shapes/big1
sudo lfs path2fid /mnt/testfs/shapes/big1
echo
echo "=== the one tier-2 object (external EA): which is it? ==="
sudo rmmod lfu_ring 2>/dev/null
sudo insmod src/kernel/lfu_ring.ko dev=testfs-MDT0000-osd
sudo timeout 180 build/lfu-scan-kmdt --stripe-count +8 /dev/lfu_scan 2>/dev/null
sudo lfs path2fid /mnt/testfs/shapes/over60
sudo lfs getstripe -c /mnt/testfs/shapes/over60 2>/dev/null | tail -1
