#!/bin/bash
# A/B for Artem's 68163 comment: an empty xattr stored in the xattr dir.
set -u
T=$HOME/lustre-a0924/lustre/utils
LFS="$T/.libs/lfs"; export LD_PRELOAD=$T/.libs/liblustreapi.so.1
P=/usr/lib64/lustre/scan_osd_zfs.so
for arm in old new; do
	sudo mount --bind $HOME/a0924-arms/$arm.so $P || exit 1
	cmp -s $P $HOME/a0924-arms/$arm.so || { echo "bind failed"; sudo umount $P; exit 1; }
	for q in "-type f" "--paths -type f" "-name f175"; do
		out=$(sudo -E $LFS find --device a0924z/mdt1 --search /tmp/a0924z $q 2>/tmp/zl.err)
		printf '%-4s %-16s n=%-4s f175:%-3s | %s\n' $arm "[$q]" \
		    "$(echo -n "$out" | grep -c .)" "$(echo "$out" | grep -c 'f175\|0x200000402:0xb0:0x0')" \
		    "$(tr '\n' ' ' < /tmp/zl.err | cut -c1-110)"
	done
	sudo umount $P
done
cmp -s $P $HOME/a0924-arms/new.so && echo "WARNING: installed plugin equals new arm"
