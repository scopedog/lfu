#!/bin/bash
# The walk with lfsp_thread_count set.  Same two nodes, fixture and predicate
# (-mtime -30 -type f) as benchsub.sh.  Five arms per scope, alternated,
# caches dropped on BOTH nodes before every run, count printed every run.
#   stock    lfs find, its own default: min(4/MDT, CPUs/2) floored at 4 = 4 here
#   ns1      llapi_scan_namespace(), lfsp_thread_count = 1 (the default)
#   ns4      llapi_scan_namespace(), lfsp_thread_count = 4 (stock's count)
#   ns8      llapi_scan_namespace(), lfsp_thread_count = 8
#   mount    llapi_scan_mount(), for reference
SRV=192.168.122.10; CLI=192.168.122.101; N=${N:-5}
SSH="ssh -o BatchMode=yes"
SCOPES=${SCOPES:-"/mnt/lustre /mnt/lustre/bench /mnt/lustre/bench/d3 /mnt/lustre/d0"}
ARMS=${ARMS:-"stock ns1 ns4 ns8 mount"}
drop() { $SSH nishida@$SRV 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'
         $SSH nishida@$CLI 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'; }
arm() {	# $1 = arm, $2 = scope
	case $1 in
	stock)	$SSH nishida@$CLI "LD=\$HOME/lustre-release/lustre/utils/.libs; s=\$(date +%s.%N); c=\$(sudo -n env LD_LIBRARY_PATH=\$LD \$LD/lfs find $2 -mtime -30 -type f 2>/dev/null | wc -l); e=\$(date +%s.%N); echo \"\$c \$(echo \"\$e-\$s\"|bc -l) stock\"" ;;
	ns*)	$SSH nishida@$CLI "s=\$(date +%s.%N); c=\$(sudo -n /tmp/subfind ns $2 ${1#ns} 2>/tmp/sub.err); e=\$(date +%s.%N); echo \"\$c \$(echo \"\$e-\$s\"|bc -l) \$(tail -1 /tmp/sub.err)\"" ;;
	mount)	$SSH nishida@$CLI "s=\$(date +%s.%N); c=\$(sudo -n /tmp/subfind mount $2 2>/tmp/sub.err); e=\$(date +%s.%N); echo \"\$c \$(echo \"\$e-\$s\"|bc -l) \$(tail -1 /tmp/sub.err)\"" ;;
	esac
}
echo "# scope                   arm      count   wall(s)  harness-line"
for scope in $SCOPES; do
  for i in $(seq $N); do
    for a in $ARMS; do
      drop; r=$(arm $a $scope)
      printf "%-25s %-7s %7s %8.3f  %s\n" $scope $a $(echo $r | cut -d' ' -f1) $(echo $r | cut -d' ' -f2) "$(echo $r | cut -d' ' -f3-)"
    done
  done
done
