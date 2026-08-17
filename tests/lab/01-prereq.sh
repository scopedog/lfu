#!/bin/bash
# Stage 1: repos and build prerequisites for a patchless-kernel ldiskfs server
# build (build_install.md §3.1), with one correction: every
# downloads.lustre.software path in that note now 404s, including the GPG key,
# so the Lustre-patched e2fsprogs comes from downloads.whamcloud.com instead.
#
# Deliberately does NOT `dnf update` the kernel: kernel-debuginfo-common must
# match the RUNNING kernel and a bump would force a reboot dance.  If
# kernel-devel/debuginfo for $(uname -r) are missing this fails loudly rather
# than quietly building without ldiskfs (§3.3 note 3: the tell-tale is a
# ~60-second build).
set -e
KVER=$(uname -r)
echo "=== kernel: $KVER"

sudo tee /etc/yum.repos.d/e2fsprogs-wc.repo > /dev/null << 'REPO'
[e2fsprogs-wc]
name=Lustre-patched e2fsprogs (whamcloud)
baseurl=https://downloads.whamcloud.com/public/e2fsprogs/latest/el9/
enabled=1
gpgcheck=0
REPO

sudo dnf -q config-manager --set-enabled crb
sudo dnf -q config-manager --set-enabled baseos-debuginfo 2>/dev/null || true
sudo dnf install -y -q https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
sudo dnf group install -y -q "Development Tools"

# The two that decide whether ldiskfs is built at all.
sudo dnf install -y "kernel-devel-$KVER" "kernel-debuginfo-common-x86_64-$KVER"

sudo dnf install -y libyaml-devel expect xmlto \
	kernel-rpm-macros kernel-abi-stablelists \
	libtool-ltdl-devel libselinux-devel python3-docutils \
	keyutils-libs-devel libmount-devel libnl3-devel \
	dwarves rpm-build git

# Patched e2fsprogs, one transaction with -devel so it cannot conflict.
sudo dnf install -y --allowerasing --nogpgcheck \
	e2fsprogs e2fsprogs-libs e2fsprogs-devel

echo "=== checks ==="
ls -d "/usr/src/kernels/$KVER" >/dev/null && echo "kernel-devel: OK"
rpm -q "kernel-debuginfo-common-x86_64-$KVER" >/dev/null && echo "debuginfo-common: OK"
if ls /usr/src/debug/kernel-*/linux-*/fs/ext4/ext4.h >/dev/null 2>&1; then
	echo "ext4 sources: OK ($(ls -d /usr/src/debug/kernel-*/linux-* | head -1))"
else
	echo "ext4 sources: MISSING -- ldiskfs would be silently skipped"; exit 1
fi
echo "e2fsprogs: $(rpm -q e2fsprogs)"
grep -q wc /dev/null; mke2fs -V 2>&1 | head -1
echo "STAGE1 OK"
