#!/bin/bash
# Round trips per arm and scope: the client's mdc req_waittime samples,
# cleared before and read after one cold run.  Run AFTER benchsub.sh, never
# during it -- clearing stats and a second client process perturb timings.
SRV=192.168.122.10; CLI=192.168.122.101
SSH="ssh -o BatchMode=yes"
SCOPES=${SCOPES:-"/mnt/lustre /mnt/lustre/bench /mnt/lustre/bench/d3 /mnt/lustre/d0"}
drop() { $SSH nishida@$SRV 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'
         $SSH nishida@$CLI 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null'; }
echo "# scope                   arm      count    RPCs-to-MDT"
for scope in $SCOPES; do
  for a in ns mount; do
    drop
    r=$($SSH nishida@$CLI "sudo -n lctl set_param -n mdc.*.stats=clear >/dev/null
      c=\$(sudo -n /tmp/subfind $a $scope 2>/dev/null)
      n=\$(sudo -n lctl get_param -n mdc.*.stats | awk '/^req_waittime/ {s+=\$2} END {print s+0}')
      echo \$c \$n")
    printf "%-25s %-7s %7s  %9s\n" $scope $a $r
  done
done
