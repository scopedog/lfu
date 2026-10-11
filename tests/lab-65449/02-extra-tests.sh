
# ---- 65449 review: extra observations, not assertions --------------------
r65449_scrub_info() {
	do_facet mds1 "$LCTL get_param -n osd-*.$(facet_svc mds1).oi_scrub" |
		grep -E "^(status|flags|time_since_latest_start|updated|failed|checked):" |
		tr '\n' ' '
	echo
}

test_90a() {
	[ "$mds1_FSTYPE" != "ldiskfs" ] && skip "ldiskfs only test"
	check_mount_and_prep
	mkdir_on_mdt0 $DIR/$tdir/d || error "mkdir failed"
	echo hello > $DIR/$tdir/d/victim || error "create failed"
	echo hello > $DIR/$tdir/d/bystander || error "create failed"
	local fid=$($LFS path2fid $DIR/$tdir/d/victim)
	echo "R2 victim FID $fid"
	cleanup_mount $MOUNT > /dev/null || error "Fail to stop client!"
	do_nodes $(mdts_nodes) "$LCTL set_param -n osd*.*MDT*.force_sync=1"
	sleep 3
	local dev=$(mdsdevname 1)
	local mnt=/mnt/r65449-brpt
	stop mds1 || error "stop mds1 failed"
	do_facet mds1 "mkdir -p $mnt && mount -t ldiskfs -o loop $dev $mnt" ||
		error "ldiskfs mount failed"
	local f=$mnt/ROOT/$tdir/d/victim
	local lma=$(do_facet mds1 "getfattr -e hex -n trusted.lma $f 2>/dev/null" |
		    awk -F= '/trusted.lma/ { print $2 }')
	echo "R2 lma before $lma"
	# struct lustre_mdt_attrs: compat(4) incompat(4) f_seq(8) f_oid(4) f_ver(4)
	# bump the third byte of f_oid: hex digits 37-38 after the 0x
	local new=$(python3 -c "
s='$lma'[2:]
b=bytearray.fromhex(s)
b[18]=(b[18]+1)&0xff
print('0x'+b.hex())")
	echo "R2 lma after  $new"
	do_facet mds1 "setfattr -n trusted.lma -v $new $f && umount $mnt" ||
		error "setfattr failed"
	start mds1 $dev $MDS_MOUNT_OPTS > /dev/null || error "start mds1 failed"
	do_facet mds1 "$LCTL get_param osd-*.$(facet_svc mds1).auto_scrub"
	echo "R2 scrub before: $(r65449_scrub_info)"
	do_facet mds1 "dmesg -C"
	mount_client $MOUNT || error "Fail to start client!"
	local rc
	timeout 120 stat $DIR/$tdir/d/victim > /dev/null 2>$TMP/r65449.err; rc=$?
	echo "R2 first stat rc=$rc $(cat $TMP/r65449.err)"
	sleep 10
	echo "R2 scrub after:  $(r65449_scrub_info)"
	echo "R2 trigger messages: $(do_facet mds1 "dmesg" | grep -c 'trigger OI scrub')"
	do_facet mds1 "dmesg" | grep -E "trigger OI scrub|LBUG|ASSERT" | tail -3
	timeout 120 stat $DIR/$tdir/d/victim > /dev/null 2>$TMP/r65449.err; rc=$?
	echo "R2 second stat rc=$rc $(cat $TMP/r65449.err)"
	timeout 60 cat $DIR/$tdir/d/bystander; echo "R2 bystander rc=$?"
	timeout 60 ls $DIR/$tdir/d; echo "R2 ls rc=$?"
}
run_test 90a "65449 review: lookup of an object whose LMA FID mismatches"

test_90b() {
	[ "$mds1_FSTYPE" != "ldiskfs" ] && skip "ldiskfs only test"
	check_mount_and_prep
	local n=20000
	local t=$LUSTRE
	mkdir_on_mdt0 $DIR/$tdir/s || error "mkdir failed"
	createmany -m $DIR/$tdir/s/f $n > /dev/null || error "createmany failed"
	do_nodes $(mdts_nodes) "$LCTL set_param -n osd*.*MDT*.force_sync=1"
	sleep 2
	local tgt=$(facet_svc mds1)
	lsmod | grep -q '^lfu ' || insmod $t/lfu/lfu.ko || error "insmod lfu failed"
	mount --bind $t/utils/scan_osd_kernel.so /usr/lib64/lustre/scan_osd_kernel.so
	stack_trap "umount /usr/lib64/lustre/scan_osd_kernel.so" EXIT
	local lfind=$t/utils/lfind
	local walk=$($LFS find $DIR/$tdir/s -type f | wc -l)
	local idle=$($lfind --target $tgt -type f 2>$TMP/r65449.err | wc -l)
	echo "S1 walk under s: $walk   OSD scan of $tgt, idle: $idle  $(head -2 $TMP/r65449.err)"
	# a slow full scrub, so the scans overlap it
	do_facet mds1 "$LCTL lfsck_start -M $tgt -t scrub -r -s 2000" ||
		error "lfsck_start failed"
	local i c st
	for i in 1 2 3; do
		st=$(do_facet mds1 "$LCTL get_param -n osd-*.$tgt.oi_scrub" |
		     awk '/^status:/ { print $2 }')
		c=$($lfind --target $tgt -type f 2>$TMP/r65449.err | wc -l)
		echo "S1 scan $i during scrub ($st): $c  $(head -2 $TMP/r65449.err)"
	done
	wait_update_facet mds1 "$LCTL get_param -n osd-*.$tgt.oi_scrub |
		awk '/^status/ { print \\\$2 }'" "completed" 120 ||
		echo "S1 scrub did not complete in 120s"
	echo "S1 scrub end: $(r65449_scrub_info)"
	c=$($lfind --target $tgt -type f 2>$TMP/r65449.err | wc -l)
	echo "S1 scan after scrub: $c"
	echo "S1 dmesg: $(dmesg | grep -cE 'LBUG|ASSERTION|BUG:|Call Trace')"
	[ "$idle" -ge "$walk" ] || error "OSD scan saw $idle < walk $walk"
}
run_test 90b "65449 review: OSD scan (DOIF_PARALLEL) while OI scrub runs"
