#!/bin/bash
# Requests in flight per arm: the client's mdc req_waittime summed over one
# cold run, divided by that run's wall.  ~1 is one request at a time; above 1
# the arm issues several at once.  Run AFTER benchthreads.sh, never during it.
SRV=192.168.122.10; CLI=192.168.122.101
SSH="ssh -o BatchMode=yes"
SCOPES=${SCOPES:-"/mnt/lustre /mnt/lustre/bench/d3"}
ARMS=${ARMS:-"stock ns1 ns4 ns8"}
drop() { $SSH nishida@$SRV 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'
         $SSH nishida@$CLI 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'; }
echo "# scope                  arm     count   wall    user   sys     getattrs  avg-us  waits(s)  in-flight"
for scope in $SCOPES; do
  for a in $ARMS; do
    drop
    $SSH nishida@$CLI "sudo -n lctl set_param -n mdc.*.stats=clear >/dev/null
      LD=\$HOME/lustre-release/lustre/utils/.libs
      case $a in
      stock) /usr/bin/time -f '%e %U %S' -o /tmp/t.x sudo -n env LD_LIBRARY_PATH=\$LD \$LD/lfs find $scope -mtime -30 -type f > /tmp/o.x 2>/dev/null; c=\$(wc -l < /tmp/o.x) ;;
      ns*)   /usr/bin/time -f '%e %U %S' -o /tmp/t.x sudo -n /tmp/subfind ns $scope ${a#ns} > /tmp/o.x 2>/dev/null; c=\$(cat /tmp/o.x) ;;
      esac
      read w u s < /tmp/t.x
      sudo -n lctl get_param -n mdc.*.stats | awk -v a=$a -v sc=$scope -v c=\$c -v w=\$w -v u=\$u -v s=\$s '
        \$1==\"mds_getattr_lock\" {g=\$2}
        \$1==\"req_waittime\" {n=\$2; sum=\$7}
        END {printf \"%-24s %-6s %6s %6.2f %6.2f %6.2f  %8d  %6d  %8.2f  %8.2f\n\", sc, a, c, w, u, s, g, (n? sum/n : 0), sum/1e6, (w>0? sum/1e6/w : 0)}'"
  done
done
