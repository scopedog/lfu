#!/bin/bash
# 10-14 lab: the forked series, each change tested where it now sits.
# f1 68416'  f2 68417'  f3 68418'  f4 69502' (on 69501' on 68417')
# f5 68726' (on 68415')  f6 69500' (trunk tip)  f7 69503' (on 68163')
# Build each arm, then sanity (02-sanity.sh's list) on ldiskfs, and on
# ZFS for f6 and f7.  Run as nishida; sanity steps use sudo.
OUT=/tmp/lab1014-fork.txt; : > $OUT
for a in f1 f2 f3 f4 f5 f6 f7; do
	bash /tmp/01-build.sh $a > /tmp/build-$a.out 2>&1
	echo "$a ($(cat /tmp/lab1009-$a.sha)) build: $(tail -1 /tmp/build-$a.out)" >> $OUT
	grep -q BUILD-OK /tmp/build-$a.out || continue
	for fs in ldiskfs $( [ $a = f6 -o $a = f7 ] && echo zfs ); do
		sudo bash /tmp/02-sanity.sh $a $fs
		echo "  $a $fs: $(grep -E '^PASS ' /tmp/lab1009-$a-sanity-$fs/run.txt) $(grep -E 'ABORT' /tmp/lab1009-$a-sanity-$fs/run.txt)" >> $OUT
		grep -E "FAIL|SKIP" /tmp/lab1009-$a-sanity-$fs/verdicts.txt | sed 's/^/    /' >> $OUT
		grep -E "^(PASS|FAIL)" /tmp/lab1009-$a-sanity-$fs/verdicts.txt | awk '{print $2}' | tr '\n' ' ' | sed 's/^/    ran: /' >> $OUT; echo >> $OUT
	done
done
echo "FORK LAB DONE" >> $OUT
