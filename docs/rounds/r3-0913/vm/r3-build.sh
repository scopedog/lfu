#!/bin/bash
# Round 3 (2026-09-13): build the fixed arm in ~/lustre-68160 (unfixed arm
# already saved in ~/r3-unfixed), copy it aside, and build the two probes.
set -u
T=/home/nishida/lustre-68160
F=/home/nishida/r3-fixed
cd $T || exit 1
git status --short | grep -v '^??' && { echo "ABORT: tracked changes in $T"; exit 2; }
git fetch -q /home/nishida/r3.bundle +r3-0913:r3fix || exit 3
git checkout -q r3fix || exit 4
echo "tree at $(git log -1 --format='%h %s')"
before=$(stat -c %Y lustre/utils/.libs/liblustreapi.so.1.0.0)
make -C lustre/utils -j4 > ~/r3-build.log 2>&1
echo "UTILS_RC=$?"
make -C lustre/tests -j4 >> ~/r3-build.log 2>&1
echo "TESTS_RC=$?"
grep -E "error:|warning:" ~/r3-build.log | head -5
after=$(stat -c %Y lustre/utils/.libs/liblustreapi.so.1.0.0)
echo "lib mtime advanced: $([ $after -gt $before ] && echo yes || echo NO)"
ls -la --time-style=+%T lustre/tests/.libs/llapi_scan_test \
	lustre/tests/.libs/llapi_scan_changelog_test \
	lustre/tests/.libs/llapi_scan_device_test lustre/utils/.libs/lfs
rm -rf $F; mkdir -p $F
cp -a lustre/utils/.libs/liblustreapi.so.1.0.0 $F/
ln -s liblustreapi.so.1.0.0 $F/liblustreapi.so.1
git rev-parse --short HEAD > $F/SHA
# the fixed library carries the new strings, the unfixed one does not
for d in /home/nishida/r3-unfixed $F; do
	echo "$d: $(grep -c 'are not in the answer' $d/liblustreapi.so.1.0.0) $(grep -ac 'cannot count the MDTs' $d/liblustreapi.so.1.0.0)"
done
I="-I$T/include -I$T/include/uapi"
gcc -Wall -o ~/r3-gotprobe ~/r3-gotprobe.c $I -L$T/lustre/utils/.libs -llustreapi && echo gotprobe-ok
gcc -Wall -shared -fPIC -o ~/r3-shim.so ~/r3-shim.c $I -ldl && echo shim-ok
echo BUILD-DONE
