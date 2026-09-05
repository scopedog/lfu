#!/bin/bash
L=/home/nishida/lustre-release
LIB=$L/lustre/utils/.libs/liblustreapi.so
echo "=== 1. is the SINGLE-OPEN fix actually in the built library?"
grep -c "the mount given is of" <(strings $LIB) && echo "   NEW message present (fix is in)" || echo "   NEW message ABSENT"
grep -c "is a mount of" <(strings $LIB) && echo "   OLD message present (fix NOT in)" || echo "   old message gone"
echo "=== installed:"
strings /usr/lib64/liblustreapi.so* 2>/dev/null | grep -c "the mount given is of"

echo "=== 2. where does it actually hang?"
pkill -9 -f lt-lfind 2>/dev/null; sleep 2
zpool list lfu-ost1 >/dev/null 2>&1 && zpool export lfu-ost1 2>/dev/null
timeout 40 $L/lustre/utils/lfind --device lfu-ost1/ost8 --fid2path /mnt/lfufs > /tmp/hang.out 2>&1 &
sleep 25
P=$(pgrep -f lt-lfind | head -1)
echo "   pid=$P  partial output lines: $(grep -c . /tmp/hang.out 2>/dev/null)"
head -3 /tmp/hang.out 2>/dev/null | sed 's/^/     /'
echo "   --- main thread stack (kernel):"
cat /proc/$P/stack 2>/dev/null | head -8 | sed 's/^/     /'
echo "   --- syscall: $(cat /proc/$P/syscall 2>/dev/null | cut -d' ' -f1)"
echo "   --- wchan: $(cat /proc/$P/wchan 2>/dev/null)"
echo "   --- threads: $(ls /proc/$P/task 2>/dev/null | wc -l)"
echo "   --- last strace (5s):"
timeout 5 strace -p $P -f -e trace=ioctl,openat 2>&1 | head -12 | sed 's/^/     /'
wait
echo "=== 3. is OST0008 still ACTIVE on the client while its pool is exported?"
lctl get_param -n osc.lfufs-OST0008*.active 2>/dev/null
lctl get_param -n lov.lfufs-*.target_obd 2>/dev/null | tail -3
pkill -9 -f lt-lfind 2>/dev/null
echo DONE
