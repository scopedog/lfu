#!/bin/bash
# Stage 1: build prerequisites plus OpenZFS from DKMS.  Same as tests/lab-zfs
# stage 1 -- kernel-devel for the DKMS build, and no `dnf update`, because a
# kernel bump leaves the DKMS module built for the wrong one.
set -e
KVER=$(uname -r)
echo "=== kernel: $KVER"

sudo dnf -q config-manager --set-enabled crb
sudo dnf install -y -q https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
sudo dnf group install -y -q "Development Tools"
sudo dnf install -y -q "kernel-devel-$KVER"
sudo dnf install -y -q libyaml-devel expect xmlto kernel-rpm-macros \
	kernel-abi-stablelists libtool-ltdl-devel libselinux-devel \
	python3-docutils keyutils-libs-devel libmount-devel libnl3-devel \
	dwarves rpm-build git libblkid-devel libuuid-devel libtirpc-devel \
	python3-devel python3-setuptools ncompress

echo "=== OpenZFS (DKMS) ==="
sudo dnf install -y -q https://zfsonlinux.org/epel/zfs-release-2-3$(rpm --eval "%{dist}").noarch.rpm || \
sudo dnf install -y -q https://zfsonlinux.org/epel/zfs-release-2-2$(rpm --eval "%{dist}").noarch.rpm
sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-openzfs* 2>/dev/null || true
sudo dnf -q config-manager --disable zfs 2>/dev/null || true
sudo dnf -q config-manager --enable zfs-kmod-dkms 2>/dev/null || \
	sudo dnf -q config-manager --enable zfs 2>/dev/null || true
sudo dnf install -y zfs zfs-dkms libzfs5-devel

sudo modprobe zfs
echo "zfs module: $(cat /sys/module/zfs/version 2>/dev/null)"
ZVER=$(ls -d /usr/src/zfs-* 2>/dev/null | head -1)
echo "zfs source: $ZVER"
[ -n "$ZVER" ] || { echo "no /usr/src/zfs-* -- DKMS source missing"; exit 1; }
ls -d /var/lib/dkms/zfs/*/"$KVER"/x86_64 || { echo "DKMS object dir missing"; exit 1; }

echo "=== the scan plugin needs libzpool's headers in userspace too ==="
ls /usr/include/libzfs/sys/dmu.h /usr/include/libspl/sys/stat.h
ls /usr/lib64/libzpool.so* 2>/dev/null || ls /lib64/libzpool.so*
echo "STAGE1 OK"
