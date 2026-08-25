#!/bin/bash
# Stage 4: llapi_scan_changelog() against a real changelog.
#
# The changelog user is registered here rather than by the library, which is
# the design's rule: registering without consuming is how an MDT fills up, so
# it stays the caller's decision.  Deregistered again at the end, so the lab
# does not leave a user accruing records behind it.
set -e
L=/home/nishida/lustre-release
MDT=testfs-MDT0000
MNT=/mnt/testfs
T=$L/lustre/tests/llapi_scan_changelog_test

echo "=== register a changelog user"
# -m is not decoration: a user registered without a mask or a name is written
# as CHANGELOG_USER_REC, and mdd_changelog_user_lookup_cb() matches only
# CHANGELOG_USER_REC2, so llapi_changelog_start_user() -- and lfs changelog
# --user -- answer -ENOENT for it.  Registering with a mask writes REC2.
USER=$(sudo lctl --device $MDT changelog_register -n \
	-m MARK,CREAT,MKDIR,HLINK,SLINK,MKNOD,UNLNK,RMDIR,RENME,RNMTO,CLOSE,LYOUT,TRUNC,SATTR,XATTR,HSM,MTIME,CTIME,MIGRT)
echo "  registered: $USER"
# and the user stays registered for the whole run: deregistering the last one
# purges the log, which is what made an earlier run read an empty changelog
trap 'sudo lctl --device '"$MDT"' changelog_deregister '"$USER"' || true' EXIT

echo "=== the mask the server records"
sudo lctl get_param -n mdd.$MDT.changelog_mask | head -2

echo "=== make events"
sudo rm -rf $MNT/clab
mkdir -p $MNT/clab
for i in $(seq 1 20); do echo hello > $MNT/clab/f$i; done
# a burst on one file: object mode has to collapse this
for i in $(seq 1 30); do echo x >> $MNT/clab/f1; sync; done
mv $MNT/clab/f2 $MNT/clab/renamed
rm -f $MNT/clab/f3
mkdir $MNT/clab/subdir
sync; sleep 2

echo "=== what lfs changelog says is there"
sudo lfs changelog $MDT | tail -5
echo "  total records: $(sudo lfs changelog $MDT | wc -l)"

echo "=== the test binary"
if [ ! -x $T ]; then
	echo "  not built by make; building it directly"
	gcc -o /tmp/cltest $L/lustre/tests/llapi_scan_changelog_test.c \
		$L/lustre/tests/llapi_test_utils.c \
		-I $L/include -I $L/include/uapi -I $L/lustre/tests \
		-D_GNU_SOURCE -Wall \
		-L $L/lustre/utils/.libs -llustreapi -lpthread || exit 1
	T=/tmp/cltest
	export LD_LIBRARY_PATH=$L/lustre/utils/.libs
fi

echo "=== run it"
sudo -E $T -m $MDT -d $MNT -u "$USER"

echo "=== and the same events through lfs changelog, for the counts"
sudo lfs changelog $MDT | awk '{print $3}' | sort | uniq -c | sort -rn | head
echo "STAGE4 DONE"
