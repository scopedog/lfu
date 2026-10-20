#!/bin/bash
# 10-20 tenant lab, client side (as root on rhel9.7-client-clone).
# Usage: 03-tenant-cli.sh up|scan <label>|caps|down
set -u
T=/tmp/stale-ten; OUT=/tmp/ten-out; mkdir -p $OUT
case $1 in
up)
	(cd $T/lustre/tests && LUSTRE=$T/lustre bash -c '. ./test-framework.sh; init_test_env >/dev/null 2>&1; load_modules') > $OUT/load.txt 2>&1
	k=$(find $T/lustre -name mdc.ko | head -1)
	[ "$(cat /sys/module/mdc/srcversion)" = "$(modinfo -F srcversion $k)" ] || { echo "ABORT: mdc not ten's"; exit 4; }
	mkdir -p /mnt/lustre
	mount -t lustre 192.168.122.10@tcp:/lustre /mnt/lustre || exit 4
	echo "client up: $(ls /mnt/lustre/ten | wc -l) files visible" ;;
scan)
	$T/mountdump /mnt/lustre > $OUT/$2.txt 2> $OUT/$2.err
	echo "$2: rc=$? records=$(wc -l < $OUT/$2.txt) ten=$(grep -c ' [tgu][0-9]* ' $OUT/$2.txt) t=$(grep -c ' t[0-9]* ' $OUT/$2.txt) g=$(grep -c ' g[0-9]* ' $OUT/$2.txt) u=$(grep -c ' u[0-9]* ' $OUT/$2.txt) | $(tr '\n' ' ' < $OUT/$2.err)"
	grep -m2 ' t[0-9]* ' $OUT/$2.txt; grep -m1 ' g[0-9]* ' $OUT/$2.txt ;;
caps)	# item 1: the client checks CAP_DAC_READ_SEARCH, not CAP_SYS_ADMIN
	runuser -u nobody -- $T/mountdump /mnt/lustre > /dev/null 2> $OUT/nocap.err
	echo "nobody, no caps: rc=$? $(tr '\n' ' ' < $OUT/nocap.err)"
	capsh --caps="cap_dac_read_search+eip cap_setpcap,cap_setuid,cap_setgid+ep" \
		--keep=1 --user=nobody --addamb=cap_dac_read_search -- \
		-c "$T/mountdump /mnt/lustre" > $OUT/cap.txt 2> $OUT/cap.err
	echo "nobody + CAP_DAC_READ_SEARCH: rc=$? records=$(wc -l < $OUT/cap.txt) $(tr '\n' ' ' < $OUT/cap.err)"
	capsh --caps="cap_sys_admin+eip cap_setpcap,cap_setuid,cap_setgid+ep" \
		--keep=1 --user=nobody --addamb=cap_sys_admin -- \
		-c "$T/mountdump /mnt/lustre" > /dev/null 2> $OUT/sysadm.err
	echo "nobody + CAP_SYS_ADMIN only: rc=$? $(tr '\n' ' ' < $OUT/sysadm.err)" ;;
down)
	umount /mnt/lustre; $T/lustre/scripts/lustre_rmmod >/dev/null 2>&1
	lsmod | grep -cE '^(lnet|obdclass) ' ;;
esac
