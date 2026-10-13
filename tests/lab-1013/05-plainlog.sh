#!/bin/bash
# 10-13 lab (as root on the clone VM): where a plain changelog reader stops.
# From the source: the client copies an llog header once, when it opens that
# log, and llog_process_thread() calls back only for indexes set in that
# copy's bitmap.  The catalog is opened when the read starts; each plain log
# when the read reaches it.  So the prediction is
#  P3: a reader stalled in the FIRST plain log sees what is appended to the
#      last plain log the catalog already listed, and nothing in a plain log
#      created later: 100000 records, 50000 appended -> more than 100002 and
#      fewer than 150002 (the end of the second plain log).
#  C2: lfs find --changelog --resolve -printf with +OPEN and 150000 files,
#      so the cache (100000) evicts and looks up before the last plain log
#      is opened: some files print twice, and the run still ends.
# Usage: 05-plainlog.sh <arm>
set -u
ARM=$1
T=/tmp/lab1009-$ARM; P=/tmp/arm1009$ARM; LFS=$T/lustre/utils/.libs/lfs
O=/tmp/lab1013-pl; rm -rf $O; mkdir -p $O
exec > $O/run.txt 2>&1
echo "== start $(date '+%F %T') ARM=$ARM ($(cat /tmp/lab1009-$ARM.sha))"
mount | grep -q ' type lustre' && { echo "ABORT: a Lustre filesystem is mounted"; exit 2; }
cd /usr/lib64/lustre/tests
export FSNAME=lfst MDSCOUNT=1 OSTCOUNT=2 LUSTRE=/usr/lib64/lustre MDSSIZE=2000000
M=/mnt/lfst; MDT=lfst-MDT0000
cur() { lctl get_param -n mdd.$MDT.changelog_users | awk '/current.index/ { print $NF }'; }
fresh() {
	env REFORMAT=yes bash ./llmount.sh > $O/llmount.txt 2>&1
	mount -t lustre | grep -q "on $M " || { echo "ABORT: no client mount"; exit 4; }
	U=$(lctl --device $MDT changelog_register -n)
}
make() {	# dir count
	mkdir $M/$1 && ./createmany -m $M/$1/f $2 > /dev/null ||
		{ echo "ABORT: cannot create $2 files in $1"; exit 5; }
	sync; sleep 2
}

fresh
make a 100000
end0=$(cur)
lfs changelog $MDT | awk 'NR == 100 { system("sleep 60") } { last = $1 } END { print NR, last }' > $O/P3.txt &
pid=$!
sleep 3
make b 50000
end1=$(cur)
wait $pid
read n last < $O/P3.txt
echo "P3: log 1..$end0 when the reader started, ..$end1 after 50000 more creates; the reader returned $n records, the last one $last ($(( last - end0 )) past its starting end)"
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"

fresh
lctl set_param -n mdd.$MDT.changelog_mask="+OPEN"
make c 150000
before=$(cur); t0=$(date +%s)
echo "--- C2: 150000 files, mask [$(lctl get_param -n mdd.$MDT.changelog_mask)], log 1..$before"
LD_PRELOAD=$P/lib/liblustreapi.so.1 timeout 900 $LFS find $M --changelog $MDT \
	--resolve -printf "%p\n" > $O/C2.out 2> $O/C2.err
rc=$?
sort $O/C2.out | uniq -c | awk '{ h[$1]++ } END { for (k in h) printf "printed x%d: %d paths; ", k, h[k]; print "" }' > $O/C2.hist
echo "C2: rc=$rc (124 = still running at 900s) in $(( $(date +%s) - t0 ))s; lines=$(wc -l < $O/C2.out) distinct=$(sort -u $O/C2.out | wc -l); log index $before -> $(cur); err: $(head -2 $O/C2.err | tr '\n' '|')"
echo "C2: $(cat $O/C2.hist)"
echo "C2 repeated, first and last: $(sort $O/C2.out | uniq -d | sort -V | sed -n '1p;$p' | tr '\n' ' ')"
lctl --device $MDT changelog_deregister $U > /dev/null
bash ./llmountcleanup.sh > $O/cleanup.txt 2>&1; echo "cleanup rc=$?"
echo "== end $(date '+%F %T')"
echo PLAINLOG DONE
