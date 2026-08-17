#!/bin/bash
# Stage 4: three more OSTs (so stripe counts and OST lists are testable), an
# OST pool, SOM enabled, and one object per shape the filter tests care about.
# SOM is enabled BEFORE the files are written, because trusted.som is written
# on close -- a file closed before SOM was on has none, which is exactly the
# "undecided" population §4.4 describes and which we also want a sample of.
set -e
NID=$(sudo lctl list_nids | head -1)
SZ=$((8 * 1024 * 1024))

echo "=== a file with NO som, written before SOM is enabled (undecided sample) ==="
sudo mkdir -p /mnt/testfs/pre
sudo dd if=/dev/urandom of=/mnt/testfs/pre/nosom1 bs=1M count=3 status=none
sudo sync

echo "=== 3 more OSTs ==="
for i in 1 2 3; do
	[ -f /lustre/ost$i.img ] || sudo truncate -s 8G /lustre/ost$i.img
	sudo mkfs.lustre --fsname=testfs --ost --index=$i --reformat \
		--device-size=$SZ --mgsnode="$NID" /lustre/ost$i.img >/dev/null 2>&1
	sudo mkdir -p /mnt/testfs-ost$i
	sudo mount -t lustre -o loop /lustre/ost$i.img /mnt/testfs-ost$i
done
sleep 5
sudo lfs df 2>/dev/null | grep -c OST || true

echo "=== an OST pool ==="
sudo lctl pool_new testfs.fast 2>/dev/null || true
sudo lctl pool_add testfs.fast OST0000 OST0001 2>/dev/null || true
sleep 2
sudo lctl pool_list testfs.fast || true

echo "=== SOM ==="
sudo lctl get_param mdt.*.enable_som || true
sudo lctl set_param -P mdt.*.enable_som=1
sleep 3
sudo lctl get_param mdt.*.enable_som || true

echo "=== object shapes ==="
cd /mnt/testfs
sudo mkdir -p shapes
cd shapes
# 1 stripe (the default), with real data so SOM size is meaningful
sudo dd if=/dev/urandom of=plain1 bs=1M count=2 status=none
# 4 stripes
sudo lfs setstripe -c 4 striped4 && sudo dd if=/dev/urandom of=striped4 bs=1M count=8 status=none
# a big one, 1.5 GiB, so --blocks/--size +1G has a real target
sudo lfs setstripe -c 4 big1 && sudo dd if=/dev/zero of=big1 bs=1M count=1536 status=none
# overstriped: 60 stripes over 4 OSTs -> a LOV too big for a 1 KiB inode,
# which is the tier-2 external-EA path
sudo lfs setstripe -C 60 over60 && sudo dd if=/dev/urandom of=over60 bs=1M count=4 status=none
# pooled
sudo lfs setstripe -p fast pooled1 && sudo dd if=/dev/urandom of=pooled1 bs=1M count=2 status=none
# data-on-MDT, then OST components
sudo lfs setstripe -E 64K -L mdt -E -1 -c 2 dom1 && sudo dd if=/dev/urandom of=dom1 bs=1M count=2 status=none
# two names for one object: a linkea with 2 entries
sudo dd if=/dev/urandom of=report_2026.csv bs=4K count=1 status=none
sudo ln report_2026.csv second_link.txt
# projid and immutable
sudo dd if=/dev/urandom of=proj1999 bs=4K count=1 status=none
sudo lfs project -p 1999 -s proj1999 2>/dev/null || sudo chattr -p 1999 proj1999 2>/dev/null || echo "(projid set failed)"
sudo dd if=/dev/urandom of=immutable1 bs=4K count=1 status=none
sudo chattr +i immutable1 2>/dev/null || echo "(chattr +i failed)"
# an empty file: a layout but no objects yet -> i_size authoritative
sudo touch empty1
# a striped directory is not possible with one MDT; note it
sudo mkdir -p adir

# bulk, so the scan has volume: 20k mknod objects
sudo mkdir -p /mnt/testfs/bulk
if command -v createmany >/dev/null 2>&1; then
	sudo createmany -m /mnt/testfs/bulk/f 20000 >/dev/null 2>&1 || true
else
	sudo bash -c 'for i in $(seq 1 2000); do : > /mnt/testfs/bulk/f$i; done'
fi
sudo sync
echo "objects in bulk: $(sudo ls /mnt/testfs/bulk | wc -l)"

echo "=== what got written ==="
cd /mnt/testfs/shapes
for f in plain1 striped4 big1 over60 pooled1 dom1 report_2026.csv proj1999 immutable1 empty1 ../pre/nosom1; do
	printf '%-18s ' "$(basename $f)"
	c=$(sudo lfs getstripe -c "$f" 2>/dev/null | tail -1)
	sz=$(sudo stat -c %s "$f" 2>/dev/null)
	som=$(sudo getfattr -n trusted.som --only-values -e hex "$f" 2>/dev/null | head -c 16)
	printf 'stripes=%-4s size=%-12s som=%s\n' "${c:-?}" "${sz:-?}" "${som:+yes}${som:-NO}"
done
echo "STAGE4 OK"
