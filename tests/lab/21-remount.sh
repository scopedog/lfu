#!/bin/bash
# Bring our filesystem back after the instance stop/start, and confirm the
# object shapes the comparison needs are still there.
set -e
cd ~/lustre-release
sudo depmod -a
sudo modprobe lustre
sudo modprobe osd_ldiskfs
echo "=== whose modules are loaded? ==="
modinfo osd_ldiskfs | grep -E '^filename|^version'
modinfo osd_ldiskfs | grep -cE 'lfu_blockparse' && echo "  (ours: LFU parms present)"
sudo lnetctl lnet configure 2>/dev/null || true
sudo lnetctl net add --net tcp0 --if $(ip -o -4 route show to default | awk '{print $5}') 2>/dev/null || true
NID=$(sudo lctl list_nids | head -1); echo "NID=$NID"

sudo mkdir -p /mnt/testfs-mdt0 /mnt/testfs /mnt/testfs-ost{0,1,2,3}
sudo mount -t lustre -o loop /lustre/mdt.img /mnt/testfs-mdt0
for i in 0 1 2 3; do sudo mount -t lustre -o loop /lustre/ost$i.img /mnt/testfs-ost$i; done
sleep 4
sudo mount -t lustre "$NID":/testfs /mnt/testfs
df -h /mnt/testfs | tail -1
echo "=== the shapes the comparison needs ==="
for f in shapes/big1 shapes/striped4 shapes/over60 shapes/pooled1; do
	printf '%-18s ' "$(basename $f)"
	printf 'client-size=%-12s stripes=%-4s fid=%s\n' \
		"$(sudo stat -c %s /mnt/testfs/$f 2>/dev/null)" \
		"$(sudo lfs getstripe -c /mnt/testfs/$f 2>/dev/null | tail -1)" \
		"$(sudo lfs path2fid /mnt/testfs/$f 2>/dev/null)"
done
echo "objects: $(sudo ls /mnt/testfs/many 2>/dev/null | wc -l) in many/, $(sudo ls /mnt/testfs/bulk 2>/dev/null | wc -l) in bulk/"
echo "REMOUNTED"
