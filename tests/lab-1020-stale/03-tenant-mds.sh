#!/bin/bash
# 10-20 tenant lab, MDS side (as root on rhel9.7-server-mgs-mds-clone), tree
# /tmp/stale-ten.  Usage: 03-tenant-mds.sh up|nm-off|nm-default|nm-admin|nm-tenant|down
# The fixture, made as root before any nodemap: 100 files owned in the
# tenant's UID range (t*), 50 out of it by UID but in by GID (g*), 100
# owned outside every range (u*).  Offsets: 100000, limit 100000, all three.
set -u
T=/tmp/stale-ten; L=$T/lustre/utils/lctl; CLI=192.168.122.101@tcp
export LUSTRE=$T/lustre FSTYPE=ldiskfs MDSCOUNT=1 OSTCOUNT=1 TMP=/tmp/tenfs \
	MDSSIZE=400000 OSTSIZE=800000
sync_nm() { sleep 12; $L get_param -n nodemap.active; }
case $1 in
up)
	mkdir -p /tmp/tenfs
	(cd $T/lustre/tests && bash llmount.sh) > /tmp/ten-llmount.txt 2>&1
	mount -t lustre | grep -q MDT0000 || { echo "ABORT: no MDT"; tail -20 /tmp/ten-llmount.txt; exit 4; }
	for m in obdclass ptlrpc tgt mdt; do
		k=$(find $T/lustre -name $m.ko | head -1)
		[ -z "$k" ] && continue
		[ "$(cat /sys/module/$m/srcversion)" = "$(modinfo -F srcversion $k)" ] ||
			{ echo "ABORT: loaded $m is not ten's"; exit 4; }
	done
	d=/mnt/lustre/ten; mkdir -p $d
	for i in $(seq 0 99); do touch $d/t$i $d/u$i; done
	for i in $(seq 0 49); do touch $d/g$i; done
	chown 100500:100500 $d/t*; chown 600:600 $d/u*; chown 600:100700 $d/g*
	$T/lustre/utils/lfs project -p 100900 $d/t0 2>/dev/null
	sync; sleep 5
	echo "up: $(ls $d | wc -l) files; nids $($L list_nids | tr '\n' ' ')"
	;;
nm-off)
	$L nodemap_activate 0; sync_nm ;;
nm-default)	# default nodemap: not admin, not trusted, no offset
	$L nodemap_modify --name default --property admin --value 0
	$L nodemap_modify --name default --property trusted --value 0
	$L nodemap_activate 1; sync_nm ;;
nm-admin)
	$L nodemap_modify --name default --property admin --value 1
	$L nodemap_modify --name default --property trusted --value 1
	sync_nm ;;
nm-tenant)
	$L nodemap_add tenant
	$L nodemap_add_range --name tenant --range $CLI
	$L nodemap_modify --name tenant --property admin --value 1
	$L nodemap_modify --name tenant --property trusted --value 1
	$L nodemap_add_offset --name tenant --offset 100000 --limit 100000
	sync_nm
	$L get_param nodemap.tenant.offset nodemap.tenant.ranges 2>&1 | head -6 ;;
down)
	$L nodemap_activate 0 2>/dev/null
	$L nodemap_del tenant 2>/dev/null
	(cd $T/lustre/tests && bash llmountcleanup.sh) > /tmp/ten-cleanup.txt 2>&1
	lsmod | grep -cE '^(lnet|obdclass) ' ;;
esac
