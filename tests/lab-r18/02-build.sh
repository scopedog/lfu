#!/bin/bash
# Stage 2: build round 18 -- the 18 changes on r16-work plus 68340, 68413 and
# 68414, which sit under 68415-68420 on Gerrit and whose mdd/mdc fixes the
# changelog tests need.
#
# Builds in its OWN tree ($LTREE), never in ~/lustre-release: on this VM that
# directory is somebody's working tree, 216 commits ahead of origin with
# uncommitted edits, and this script's reset --hard would destroy it.
set -e
KVER=$(uname -r)
BASE=${BASE:-5afbab284e}
SRC=${SRC:-$HOME/lustre-release}
LTREE=${LTREE:-$HOME/lustre-r18}
PATCHES=${PATCHES:-$HOME/patches-r18}

[ "$LTREE" = "$SRC" ] && { echo "refusing to build in $SRC"; exit 1; }

git config --global user.name "LFU lab" 2>/dev/null || true
git config --global user.email lfu@local 2>/dev/null || true

if [ ! -d "$LTREE" ]; then
	echo "=== cloning $SRC -> $LTREE (hardlinked)"
	git clone -q "$SRC" "$LTREE"
	git -C "$LTREE" remote set-url origin https://github.com/lustre/lustre-release.git
fi
cd "$LTREE"

# --tags is not optional: LUSTRE_VERSION comes from `git describe`, and a clone
# whose newest tag is 2.17.51 builds below the 2.17.57 gate on 160aa-ad, which
# would make every one of them skip and read as a pass.
echo "=== fetching master and tags"
git fetch -q origin master --tags
git cat-file -e "$BASE^{commit}" 2>/dev/null ||
	{ echo "cannot reach $BASE even after fetch"; exit 1; }

git reset -q --hard HEAD; git clean -qfdx
git checkout -q "$BASE"; git reset -q --hard "$BASE"; git clean -qfdx

echo "=== applying the series ==="
git am "$PATCHES"/*.patch
git log --oneline "$BASE"..HEAD | cat

# the tests this lab exists for have to be present and gated at a version the
# tree reaches, or they skip silently and prove nothing.
for t in 56El 160aa 160ab 160ac 160ad; do
	grep -q "^test_$t()" lustre/tests/sanity.sh ||
		{ echo "$t is missing from sanity.sh"; exit 1; }
done
grep -A6 "^test_160aa()" lustre/tests/sanity.sh | grep -q "2.17.57" ||
	{ echo "160aa is not gated at 2.17.57 -- it will skip"; exit 1; }

# autogen, not configure: AC_INIT bakes LUSTRE_VERSION_STRING into the
# generated configure through m4_esyscmd_s, so ./configure alone leaves
# config.h stale and the wrong version is compiled into the modules.
sh autogen.sh >/tmp/autogen.log 2>&1 || { tail -20 /tmp/autogen.log; exit 1; }
./configure --enable-server --enable-ldiskfs --disable-zfs \
	--with-linux="/usr/src/kernels/$KVER" > /tmp/configure.log 2>&1 || {
	tail -30 /tmp/configure.log; exit 1; }
grep -q "^ENABLE_LDISKFS='yes'" config.log ||
	{ echo "ENABLE_LDISKFS is not yes -- refusing to build"; exit 1; }
grep -n "LUSTRE_VERSION_STRING" config.h

t0=$(date +%s)
make -j"$(nproc)" > /tmp/make.log 2>&1 || {
	echo "BUILD FAILED"; grep -nE 'error:|Error [0-9]' /tmp/make.log | head -40; exit 1; }
echo "build took $(( $(date +%s) - t0 ))s"
sudo make install > /tmp/install.log 2>&1 || { tail -20 /tmp/install.log; exit 1; }
sudo ldconfig; sudo depmod -a

V=$(lfs --version | awk '{print $2}')
echo "installed lfs: $V"
case "$V" in 2.17.5[7-9]*|2.17.6*|2.18*) echo "userspace clears the 2.17.57 gate" ;;
*) echo "installed $V is BELOW the 2.17.57 gate"; exit 1 ;; esac

# the framework reads the LOADED module, not this tree and not lfs.  An empty
# answer is "modules not loaded", which the framework papers over by falling
# back to the userspace binary -- so assert it is non-empty here.
M=$(modinfo -F version "$LTREE"/lustre/obdclass/obdclass.ko 2>/dev/null)
echo "obdclass.ko version: ${M:-<empty>}"
[ -n "$M" ] || { echo "module carries no version"; exit 1; }
case "$M" in 2.17.5[7-9]*|2.17.6*|2.18*) echo "module clears the 2.17.57 gate" ;;
*) echo "module $M is BELOW the 2.17.57 gate -- 160aa-ad would skip"; exit 1 ;; esac
echo "STAGE2 OK"
