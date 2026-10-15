#!/bin/bash
# 10-14: arms after the lreview fixes.  Build each (no-ZFS script below
# 68163), the shard A/B on s0/s1, then sanity on every changed arm.
OUT=/tmp/lab1014-fixes.txt; : > $OUT
for a in s0 s1 h1 h5; do bash /tmp/07-build-nozfs.sh $a > /tmp/build-$a.out 2>&1; echo "$a ($(cat /tmp/lab1009-$a.sha)) build: $(tail -1 /tmp/build-$a.out)" >> $OUT; done
for a in h2 h3 h4 h6 h7; do bash /tmp/01-build.sh $a > /tmp/build-$a.out 2>&1; echo "$a ($(cat /tmp/lab1009-$a.sha)) build: $(tail -1 /tmp/build-$a.out)" >> $OUT; done
sudo bash /tmp/11-shard.sh s0 s1; cat /tmp/lab1014-shard/run.txt >> $OUT
for a in s1 h1 h2 h3 h4 h5 h6 h7; do
	grep -q BUILD-OK /tmp/build-$a.out || continue
	for fs in ldiskfs $( [ $a = h6 -o $a = h7 ] && echo zfs ); do
		sudo bash /tmp/02-sanity.sh $a $fs
		echo "  $a $fs: $(grep -E '^PASS ' /tmp/lab1009-$a-sanity-$fs/run.txt) $(grep ABORT /tmp/lab1009-$a-sanity-$fs/run.txt)" >> $OUT
		grep -E "FAIL|SKIP" /tmp/lab1009-$a-sanity-$fs/verdicts.txt | sed 's/^/    /' >> $OUT
	done
done
echo "FIXES LAB DONE" >> $OUT
