#!/bin/bash
# Stage 2: build the changelog series up to 68420 -- 68419 carries the
# --since-cookie code, 68420 carries the tests, so the lab needs both.
#
# Builds in its OWN tree ($LTREE), never in ~/lustre-release.  On a reused lab
# VM that directory is somebody's working tree: the clone this lab first ran on
# had uncommitted edits to mdd_changelog.c and lwp_dev.c, ten local branches
# and a master 216 commits ahead of origin, and this script's reset --hard plus
# clean -fdx would have destroyed all of it.  The clone is hardlinked, so the
# second tree costs almost no space.
set -e
KVER=$(uname -r)
BASE=${BASE:-5afbab284e}
SRC=${SRC:-$HOME/lustre-release}
LTREE=${LTREE:-$HOME/lustre-160ac}

[ "$LTREE" = "$SRC" ] && { echo "refusing to build in $SRC"; exit 1; }

git config --global user.name "LFU lab" 2>/dev/null || true
git config --global user.email lfu@local 2>/dev/null || true

if [ ! -d "$LTREE" ]; then
	echo "=== cloning $SRC -> $LTREE (hardlinked)"
	git clone -q "$SRC" "$LTREE"
	git -C "$LTREE" remote set-url origin https://github.com/lustre/lustre-release.git
fi
cd "$LTREE"

# --tags is not optional.  LUSTRE_VERSION comes from `git describe`, so a clone
# whose newest tag is 2.17.51 builds an "lfs 2.17.51_NNN" that is BELOW the
# 2.17.57 gate on 160aa/ab/ac -- and every one of them would silently skip.
echo "=== fetching master and tags"
git fetch -q origin master --tags
git cat-file -e "$BASE^{commit}" 2>/dev/null ||
	{ echo "cannot reach $BASE even after fetch"; exit 1; }

git checkout -q "$BASE"; git reset -q --hard "$BASE"; git clean -qfdx

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

# the gate compares against the INSTALLED version, so check what we just put on
V=$(lfs --version | awk '{print $2}')
echo "installed lfs: $V"
case "$V" in 2.17.5[7-9]*|2.17.6*|2.18*) echo "version clears the 2.17.57 gate" ;;
*) echo "installed $V is BELOW the 2.17.57 gate -- 160ac would skip"; exit 1 ;; esac
echo "STAGE2 OK"
