#!/bin/bash
# Every LLAPI_SCAN_* / LFU_* the scan plugins name must be defined at that
# commit.  The per-commit build sweep cannot see this: libscan_zfs.c is
# compiled only when ZFS is enabled and the local tree is configured
# without it, so an undefined macro there is invisible until the Janitor
# builds on rocky8.10 -- which is exactly how LLAPI_SCAN_BACKEND_ABI got
# into c07 while its #define arrived at c22.
cd /home/nishida/projects/lustre/lustre-scanfid
TIP=${1:?usage: plugin-macro-check.sh TIP}
BASE=b7b1332a42a6959375c296f7a28564dcb90b2763
PLUGINS="lustre/utils/libscan_zfs.c lustre/utils/libscan_ldiskfs.c
	 lustre/utils/libscan_kernel.c lustre/utils/libscan_client.c"
HDRS="lustre/utils/lustreapi_scan_backend.h lustre/utils/lustreapi_internal.h
      include/lustre/lustreapi.h include/uapi/linux/lustre/lustre_lfu.h
      lustre/utils/lustreapi_lfu_rec.h"
bad=0
i=0
for c in $(git rev-list --reverse $BASE..$TIP); do
	# #defines and enum members both count as "defined"
	defs=$(for h in $HDRS; do git show $c:$h 2>/dev/null; done |
	       grep -oE '(^#define |^[[:space:]]*)(LLAPI_SCAN_[A-Z0-9_]+|LFU_[A-Z0-9_]+)' |
	       grep -oE '(LLAPI_SCAN_[A-Z0-9_]+|LFU_[A-Z0-9_]+)' | sort -u)
	for p in $PLUGINS; do
		src=$(git show $c:$p 2>/dev/null) || continue
		used=$(echo "$src" |
		       grep -oE '\b(LLAPI_SCAN_[A-Z0-9_]+|LFU_[A-Z0-9_]+)\b' |
		       sort -u)
		for u in $used; do
			# a bare prefix like "LFU_INFO_*" in prose is not an
			# identifier
			case $u in *_) continue;; esac
			# defined by the plugin itself, or an enum, counts too
			echo "$defs" | grep -qx "$u" && continue
			echo "$src" | grep -qE "^[[:space:]]*(#define )?$u[[:space:],=]" &&
				continue
			echo "c$(printf %02d $i) $(basename $p): $u undefined"
			bad=1
		done
	done
	i=$((i+1))
done
[ $bad -eq 0 ] && echo "PLUGIN-MACRO-CHECK CLEAN"
exit $bad
