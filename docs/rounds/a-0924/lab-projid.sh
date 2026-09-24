#!/bin/bash
# A/B for Artem's 68159 comment: --projid on an object with a torn layout.
set -uo pipefail
S=/tmp/claude-1004/-home-nishida-projects-lustre-lfu/54050a2d-d422-4ffc-b42c-854fef90fbe6/scratchpad
T=~/lfs-artem-0924
L=/home/nishida/projects/lustre/lfu/tests
W=$S/lab; rm -rf $W; mkdir -p $W; cd $W
CF=(-include $T/config.h -I $T/include -I $T/include/uapi -I $T/lustre/utils
    -D_GNU_SOURCE -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64 -DLUSTRE_UTILS=1)
gcc -shared -fPIC -Wl,--export-dynamic -o $T/lustre/utils/scan_osd_ldiskfs.so \
    $T/lustre/utils/libscan_ldiskfs.c "${CF[@]}" -lext2fs || exit 1
export LUSTRE=$T/lustre
build() {	# $1 = arm name; the tree is at that arm's commit and built
	mkdir -p $W/$1; cp -a $T/lustre/utils/.libs/liblustreapi.so* $W/$1/
	gcc -o $W/$1/tdev $L/find-device/tdev.c $T/lustre/utils/lfs_find_parse.c \
	    "${CF[@]}" -L $W/$1 -llustreapi -Wl,-rpath,$W/$1 || exit 1
	echo "$1: $(cd $T && git log -1 --format='%h %s')"
}
cd $T; git checkout -q artem-0924; (cd lustre/utils && make -j16 >/dev/null 2>&1) || exit 1; build new
git checkout -q 218cdea575; (cd lustre/utils && make -j16 >/dev/null 2>&1) || exit 1; build old
git checkout -q artem-0924; cd $W

# fixtures: built once, never touched again
bash $L/mkimage.sh $W/clean.img 64M >/dev/null 2>&1 || exit 1
tune2fs -L testfs-MDT0000 $W/clean.img >/dev/null || exit 1
cp $W/clean.img $W/torn.img
# a composite header claiming 65535 entries in a 32-byte buffer
printf '\xd0\x0b\xd6\x0b\x00\x10\x00\x00\x01\x00\x00\x00\x00\x00\xff\xff' > $W/torn.lov
printf '\x00%.0s' $(seq 16) >> $W/torn.lov
debugfs -w -R "ea_set -f $W/torn.lov proj1999 trusted.lov" $W/torn.img 2>&1 | grep -v "^debugfs"
echo "fixture: $(debugfs -R 'ea_list proj1999' $W/torn.img 2>/dev/null | tr '\n' ' ' | cut -c1-200)"

for img in clean torn; do
  for q in "--projid 1999" "! --projid 1999" "--stripe-count 1" ""; do
    o=$(LUSTRE=$T/lustre $W/old/tdev $W/$img.img $q 2>$W/e.old | sort | md5sum | cut -c1-8)
    no=$(LUSTRE=$T/lustre $W/old/tdev $W/$img.img $q 2>/dev/null | wc -l)
    nn=$(LUSTRE=$T/lustre $W/new/tdev $W/$img.img $q 2>$W/e.new | wc -l)
    n=$(LUSTRE=$T/lustre $W/new/tdev $W/$img.img $q 2>/dev/null | sort | md5sum | cut -c1-8)
    printf '%-6s %-18s old=%3s new=%3s %s | old-err: %s | new-err: %s\n' $img "[$q]" $no $nn \
      "$([ $o = $n ] && echo same || echo DIFF)" "$(tr '\n' ' ' < $W/e.old | cut -c1-90)" "$(tr '\n' ' ' < $W/e.new | cut -c1-90)"
  done
done
