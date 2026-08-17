#!/bin/bash
# Stage 4 (ZFS): one object per shape every tier-1 predicate needs, then bulk.
#
# Same shapes as the ldiskfs lab (tests/lab/04-populate.sh) minus the ones that
# only make sense there: no 60-way overstripe for an external EA block, because
# on ZFS the equivalent -- a value too large for the SA area -- is what the
# xattr-directory fallback is for, and it is provoked directly below with a big
# xattr instead.  Volume is 100k, not 300k: ZFS enumeration is ~5x slower than
# ldiskfs and 100k is ample for a rate row.
set -e
M=/mnt/lfufs
sudo mkdir -p $M/shapes && sudo chmod 777 $M/shapes $M
cd $M/shapes

echo "=== OST pool ==="
sudo lctl pool_new lfufs.fast 2>/dev/null || true
sudo lctl pool_add lfufs.fast OST0000 2>/dev/null || true
sleep 2

echo "=== shapes ==="
# 2-striped, 1.5 GiB: --blocks/--size +1G via trusted.som
lfs setstripe -c 2 big1; dd if=/dev/zero of=big1 bs=1M count=1536 status=none; sync
# pooled: --pool fast
lfs setstripe -p fast pooled1; echo x > pooled1
# 2-striped small: --stripe-count +1
lfs setstripe -c 2 striped1; echo x > striped1
# hardlinked: --name through trusted.link, 2 entries
echo x > named1; ln named1 named2
# projid
echo x > proj1; sudo lfs project -p 1999 proj1
# immutable
echo x > immut1; sudo chattr +i immut1 2>/dev/null || sudo lfs setstripe --help >/dev/null
# striped directory is single-MDT here, so no LMV shape; note it
mkdir dir1
# a deliberately large xattr: bigger than DXATTR_MAX_SA_SIZE, so it must land in
# the xattr directory -- the tier-2 path of the new code
echo x > bigxattr1
sudo setfattr -n trusted.lfu_big -v "$(head -c 200000 /dev/zero | tr '\0' 'A')" bigxattr1 2>/dev/null && \
	echo "  big xattr set" || echo "  big xattr refused (fine; tier 2 then only if a real one spills)"

echo "=== ground truth from the client ==="
for f in big1 pooled1 striped1 named1 proj1 immut1; do
	printf "%-10s fid=%s size=%s\n" "$f" "$(lfs path2fid $f)" "$(stat -c %s $f)"
done
lfs getstripe -y big1 | head -20

echo "=== bulk: 100k ==="
mkdir -p $M/bulk
t0=$(date +%s)
~/lustre-release/lustre/tests/createmany -m $M/bulk/f 100000 > /tmp/createmany.log 2>&1
echo "createmany: $(( $(date +%s) - t0 ))s"
sync
echo "objects on the MDT:"; lfs df -i $M | tail -3
echo "STAGE4 OK"
