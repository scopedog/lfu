#!/bin/bash
# Re-apply the patch and rebuild after an edit, without touching the
# filesystem images.  Everything Lustre must be unmounted before
# `make install` or it dies on a busy /sbin/mount.lustre -- after a
# successful build, which leaves the previous modules installed.
set -e
KVER=$(uname -r)
cd ~/lustre-release

sudo umount /mnt/testfs 2>/dev/null || true
sudo umount /mnt/ost0 2>/dev/null || true
sudo umount /mnt/mdt0 2>/dev/null || true

# NOT `[ -f Makefile ]`: lustre-release tracks a top-level Makefile, so it
# survives a git clean while every generated sub-Makefile does not.
[ -f config.status ] || {
	sh autogen.sh > /tmp/autogen2.log 2>&1
	./configure --enable-server --enable-ldiskfs --disable-zfs \
		--with-linux="/usr/src/kernels/$KVER" > /tmp/configure2.log 2>&1
	grep -q "^ENABLE_LDISKFS='yes'" config.log || { echo "no ldiskfs"; exit 1; }
}
make -j"$(nproc)" > /tmp/make2.log 2>&1 || {
	echo "BUILD FAILED"; grep -nE 'error:' /tmp/make2.log | head -20; exit 1; }
sudo make install > /tmp/inst2.log 2>&1 || { tail -20 /tmp/inst2.log; exit 1; }
sudo ldconfig; sudo depmod -a
nm -D --defined-only lustre/utils/.libs/liblustreapi.so.1.0.0 | grep llapi_scan_namespace

# remount the SAME images -- no mkfs, the populated tree must survive
sudo mount -t lustre -o loop ~/img/mdt.img /mnt/mdt0
sudo mount -t lustre -o loop ~/img/ost0.img /mnt/ost0
sudo mount -t lustre "$(hostname -i)@tcp:/testfs" /mnt/testfs
df -t lustre -h | tail -3
echo "REBUILD OK"
