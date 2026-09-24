#!/bin/bash
set -u
T=/home/nishida/lustre-0918/lustre/tests; M=/mnt/lustre; A=/home/nishida/lab0924-new
cd $T; ./llmountcleanup.sh >/dev/null 2>&1
MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > /tmp/sd-mount.log 2>&1
mount -t lustre | grep -q "on $M " || { echo NOMOUNT; exit 1; }
lfs mkdir -i 0 -c 2 $M/sd || exit 1
for i in $(seq 0 19); do touch $M/sd/s$i; done
echo "client: $(lfs getdirstripe -c $M/sd) stripes; per-MDT: $(for i in $(seq 0 19); do lfs getstripe -m $M/sd/s$i; done | sort | uniq -c | tr '\n' ' ')"
sync; sync; ./llmountcleanup.sh >/dev/null 2>&1
LUSTRE=$A/lustre LD_LIBRARY_PATH=$A/lustre/utils/.libs LD_PRELOAD=$A/lustre/utils/.libs/liblustreapi.so.1 \
	$A/lustre/utils/.libs/lfs find --device /tmp/lustre-mdt1 --paths -type f > /tmp/sd.out 2>&1
ns=$(grep -c "^/sd/" /tmp/sd.out); bad=$(grep "^/sd/" /tmp/sd.out | grep -vcE "^/sd/s[0-9]+$")
echo "scan of MDT0000: $ns files of /sd, $bad with a shard in the path"
grep "^/sd/" /tmp/sd.out | head -4
grep -v "^/" /tmp/sd.out | head -3
