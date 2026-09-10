#!/bin/bash
# Two-node LFU benchmark: stock lfs find (client namespace walk, one RPC per
# object) vs the offloaded Object Stream (LL_IOC_LFU_SCAN, bulk).  Arms
# alternate so drift hits both; caches are dropped on BOTH nodes before every
# run, so each is cold.  Counts are printed every run: a fast wrong answer
# must not pass as a fast one.
SRV=192.168.122.10; CLI=192.168.122.101; N=${N:-5}
SSH="ssh -o BatchMode=yes"
drop() { $SSH nishida@$SRV 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'
         $SSH nishida@$CLI 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'; }
stock() { $SSH nishida@$CLI 'L=$HOME/lustre-release/lustre/utils/.libs/lfs; LD=$HOME/lustre-release/lustre/utils/.libs
  s=$(date +%s.%N); c=$(LD_LIBRARY_PATH=$LD /usr/bin/time -f "%U %S" $L find /mnt/lustre -mtime -1 -type f 2>/tmp/t.err | wc -l); e=$(date +%s.%N)
  echo "$c $(echo "$e-$s"|bc -l) $(tail -1 /tmp/t.err)"'; }
offload() { $SSH nishida@$CLI 's=$(date +%s.%N); c=$(/usr/bin/time -f "%U %S" sudo -n /tmp/offfind /mnt/lustre 0 q 2>/tmp/t.err); e=$(date +%s.%N)
  echo "$c $(echo "$e-$s"|bc -l) $(tail -1 /tmp/t.err)"'; }
echo "# arm      count   wall(s)  user  sys"
for i in $(seq $N); do
  for arm in stock offload; do
    drop; r=$($arm)
    printf "%-9s %7s %8.3f  %s\n" $arm $(echo $r | cut -d' ' -f1) $(echo $r | cut -d' ' -f2) "$(echo $r | cut -d' ' -f3-)"
  done
done
