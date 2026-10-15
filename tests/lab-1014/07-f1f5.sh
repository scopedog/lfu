#!/bin/bash
# 10-14: f1 (68416') and f5 (68726'), which sit below 68163.
OUT=/tmp/lab1014-f1f5.txt; : > $OUT
for a in f1 f5; do
	bash /tmp/07-build-nozfs.sh $a > /tmp/build-$a.out 2>&1
	echo "$a ($(cat /tmp/lab1009-$a.sha)) build: $(tail -1 /tmp/build-$a.out)" >> $OUT
	grep -q BUILD-OK /tmp/build-$a.out || { grep -m5 " error: \|No rule" /tmp/lab1009-$a-make2.log >> $OUT; continue; }
	sudo bash /tmp/02-sanity.sh $a ldiskfs
	echo "  $a ldiskfs: $(grep -E '^PASS ' /tmp/lab1009-$a-sanity-ldiskfs/run.txt) $(grep ABORT /tmp/lab1009-$a-sanity-ldiskfs/run.txt)" >> $OUT
	grep -E "FAIL|SKIP" /tmp/lab1009-$a-sanity-ldiskfs/verdicts.txt | sed 's/^/    /' >> $OUT
	grep -E "^(PASS|FAIL)" /tmp/lab1009-$a-sanity-ldiskfs/verdicts.txt | awk '{print $2}' | tr '\n' ' ' | sed 's/^/    ran: /' >> $OUT; echo >> $OUT
done
echo "F1F5 DONE" >> $OUT
