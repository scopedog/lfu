#!/bin/bash
# Root vs subtree.  Two nodes: server .10 (MDT + OSTs), client .101.  Three
# arms per scope, alternated, caches dropped on BOTH nodes before every run.
# The count is printed every run: a fast wrong answer must not pass as fast.
# -mtime, because "-type f" alone is answered from the dirent: a readdir,
# 0.17 s cold for 88k files, measuring no per-object cost.
#   stock    lfs find SCOPE -mtime -30 -type f   ~/lustre-release, no LFU: the
#                                          baseline the earlier 30x was against
#   walk     llapi_scan_namespace(SCOPE)   asking only for what -type f needs
#   offload  llapi_scan_mount(SCOPE)       the MDT streams; subtree filtered here
# /tmp/subfind carries an rpath to /tmp/sublib: sudo resets LD_LIBRARY_PATH.
SRV=192.168.122.10; CLI=192.168.122.101; N=${N:-5}
SSH="ssh -o BatchMode=yes"
SCOPES=${SCOPES:-"/mnt/lustre /mnt/lustre/bench /mnt/lustre/bench/d3 /mnt/lustre/d0"}
drop() { $SSH nishida@$SRV 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'
         $SSH nishida@$CLI 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'; }
arm() {	# $1 = stock|ns|mount, $2 = scope
	if [ $1 = stock ]; then
		$SSH nishida@$CLI "LD=\$HOME/lustre-release/lustre/utils/.libs; s=\$(date +%s.%N); c=\$(sudo -n env LD_LIBRARY_PATH=\$LD \$LD/lfs find $2 -mtime -30 -type f 2>/tmp/sub.err | wc -l); e=\$(date +%s.%N); echo \"\$c \$(echo \"\$e-\$s\"|bc -l) stock\""
	else
		$SSH nishida@$CLI "s=\$(date +%s.%N); c=\$(sudo -n /tmp/subfind $1 $2 2>/tmp/sub.err); e=\$(date +%s.%N); echo \"\$c \$(echo \"\$e-\$s\"|bc -l) \$(tail -1 /tmp/sub.err)\""
	fi
}
echo "# scope                   arm      count   wall(s)  harness-line"
for scope in $SCOPES; do
  for i in $(seq $N); do
    for a in stock ns mount; do
      drop; r=$(arm $a $scope)
      printf "%-25s %-7s %7s %8.3f  %s\n" $scope $a $(echo $r | cut -d' ' -f1) $(echo $r | cut -d' ' -f2) "$(echo $r | cut -d' ' -f3-)"
    done
  done
done
