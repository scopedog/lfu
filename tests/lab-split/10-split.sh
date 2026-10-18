#!/bin/bash
# Where the time of a remote MDT scan goes.  Runs on the client; $1 = server.
#   raw:     LL_IOC_LFU_SCAN loop, no record walk  -> ioctl time per RPC
#   parse:   the same, walking every record        -> client decode cost
#   scanone: llapi_scan_mount(), 1 thread          -> the whole library
# bpftrace on both ends during the raw arm splits each ioctl into
# server build (dt_index_read), server handler rest (bulk send, reply),
# client RPC wait, and client ioctl rest (folio alloc, copy_to_user, free).
# Cold = page cache dropped on both nodes; warm = run right after a run.
SRV=$1; N=${N:-5}; M=/mnt/testfs; OUT=~/split; mkdir -p $OUT
drop() { ssh -o BatchMode=yes $SRV 'sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null'
	 sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; }

echo "== $(date -Is) version $(sudo lctl get_param -n version | head -1)"
echo "== net: $(ethtool eth0 2>/dev/null | grep Speed) mtu $(cat /sys/class/net/eth0/mtu)"

for i in $(seq $N); do
	for temp in cold warm; do
		[ $temp = cold ] && drop || sudo ./rsplit $M >/dev/null
		ssh -o BatchMode=yes $SRV "sudo bpftrace ~/server.bt > ~/srv.$temp.$i.txt 2>&1 & echo \$! > ~/bt.pid"
		sudo bpftrace client.bt > $OUT/cli.$temp.$i.txt 2>&1 & BT=$!
		sleep 4		# bpftrace attaches
		echo "raw $temp $i $(sudo ./rsplit $M)"
		sudo kill -INT $BT; ssh -o BatchMode=yes $SRV 'sudo kill -INT $(cat ~/bt.pid)'
		sleep 2; wait $BT 2>/dev/null
		scp -q -o BatchMode=yes $SRV:srv.$temp.$i.txt $OUT/
		echo "   cli: $(grep -h '^@' $OUT/cli.$temp.$i.txt | tr '\n' ' ')"
		echo "   srv: $(grep -h '^@' $OUT/srv.$temp.$i.txt | tr '\n' ' ')"

		[ $temp = cold ] && drop || sudo ./rsplit $M parse >/dev/null
		echo "parse $temp $i $(sudo ./rsplit $M parse)"

		[ $temp = cold ] && drop || sudo ./scanone $M >/dev/null
		t0=$(date +%s.%N); r=$(sudo ./scanone $M); t1=$(date +%s.%N)
		echo "scanone $temp $i wall $(python3 -c "print('%.4f' % ($t1 - $t0))") $r"
	done
done
echo "SPLIT DONE"
