#!/bin/bash
set -e
KVER=$(uname -r)
sudo dnf clean packages -q
sudo dnf install -y "kernel-debuginfo-common-x86_64-$KVER"
sudo dnf install -y libyaml-devel expect xmlto \
	kernel-rpm-macros kernel-abi-stablelists \
	libtool-ltdl-devel libselinux-devel python3-docutils \
	keyutils-libs-devel libmount-devel libnl3-devel \
	dwarves rpm-build git
sudo dnf install -y --allowerasing --nogpgcheck e2fsprogs e2fsprogs-libs e2fsprogs-devel
echo "=== checks ==="
ls -d "/usr/src/kernels/$KVER" >/dev/null && echo "kernel-devel: OK"
rpm -q "kernel-debuginfo-common-x86_64-$KVER" >/dev/null && echo "debuginfo-common: OK"
if ls /usr/src/debug/kernel-*/linux-*/fs/ext4/ext4.h >/dev/null 2>&1; then
	echo "ext4 sources: OK ($(ls -d /usr/src/debug/kernel-*/linux-* | head -1))"
else
	echo "ext4 sources: MISSING -- ldiskfs would be silently skipped"; exit 1
fi
echo "e2fsprogs: $(rpm -q e2fsprogs)"
mke2fs -V 2>&1 | head -1
echo "STAGE1 OK"
