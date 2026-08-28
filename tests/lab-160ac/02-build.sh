#!/bin/bash
# Stage 2: build the changelog series up to 68420 -- 68419 carries the
# --since-cookie code, 68420 carries the tests, so the lab needs both.
# Single node: MGS + 2 MDTs + OST + client, which is all 160ac needs.
set -e
KVER=$(uname -r)
BASE=${BASE:-5afbab284e}
cd ~
git config --global user.name "LFU lab"
git config --global user.email lfu@local

if [ ! -d lustre-release ]; then
	git clone -q https://github.com/lustre/lustre-release.git
fi
cd lustre-release
git fetch -q origin master
git checkout -q "$BASE"
git reset -q --hard "$BASE"
git clean -qfdx

echo "=== applying the series ==="
git am ~/patches/*.patch
git log --oneline "$BASE"..HEAD | cat

# the point of the lab: 160ac has to be present and gated at a version this
# tree reaches, or it silently skips and proves nothing.  That is the exact
# trap round 11 fixed, so assert it here rather than read it off a log later.
grep -q "^test_160ac()" lustre/tests/sanity.sh ||
	{ echo "160ac is missing from sanity.sh"; exit 1; }
grep -A4 "^test_160ac()" lustre/tests/sanity.sh | grep -q "2.17.57" ||
	{ echo "160ac is not gated at 2.17.57 -- it will skip"; exit 1; }

sh autogen.sh >/tmp/autogen.log 2>&1 || { tail -20 /tmp/autogen.log; exit 1; }
./configure --enable-server --enable-ldiskfs --disable-zfs \
	--with-linux="/usr/src/kernels/$KVER" > /tmp/configure.log 2>&1 || {
	tail -30 /tmp/configure.log; exit 1; }
grep -q "^ENABLE_LDISKFS='yes'" config.log ||
	{ echo "ENABLE_LDISKFS is not yes -- refusing to build"; exit 1; }

t0=$(date +%s)
make -j"$(nproc)" > /tmp/make.log 2>&1 || {
	echo "BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/make.log | head -40; exit 1; }
echo "build took $(( $(date +%s) - t0 ))s"
sudo make install > /tmp/install.log 2>&1 || { tail -20 /tmp/install.log; exit 1; }
sudo ldconfig; sudo depmod -a
lfs --version
echo "STAGE2 OK"
