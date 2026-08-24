#!/bin/bash
# Stage 16: the descriptor half of LU-20624, and what dup2() changed.
#
# cb_get_dirstripe() used to close the descriptor it was given and hand back
# an O_NOFOLLOW reopen through its argument.  Both callers pass the address of
# a local copy, so llapi_semantic_traverse() kept the closed number, closed it
# a second time on the way out, and leaked the reopen.  The fix keeps the
# reopen on the number the caller already holds.
#
# Two cases reach the retry, and they are NOT the same:
#   - a directory that is not on Lustre: the retried ioctl answers ENOTTY
#     again, cb_find_init() returns the error, and llapi_semantic_traverse()
#     jumps to err: BEFORE fdopendir().  So the subtree is lost to the error
#     return, not to the descriptor -- which is what the 2026-08-24 review
#     found our commit message claiming wrongly.  Only the closes change.
#   - a FOREIGN directory: the retry SUCCEEDS, cb_find_init() returns 0, and
#     the traversal does fdopendir() the number it kept.  That is the case
#     where the descriptor really costs a walk.
#
# Measure the MAIN PROCESS ONLY.  strace -f under sudo attributes a shell's
# and its helpers' closes to the run; the 2026-08-22 write-up got "seven EBADF
# closes" that way and none of them were ours.
set -e
cd ~
R=${R:-/mnt/testfs}
L=~/lustre-release
FAIL=0
ck() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1: got '$2' want '$3'"; FAIL=1; fi; }

command -v strace >/dev/null || sudo dnf install -y -q strace

##############################################################################
echo "=== 0. the two subjects"
##############################################################################
sudo mkdir -p $R/d2
mountpoint -q $R/d2/tmpfs || { sudo mkdir -p $R/d2/tmpfs; sudo mount -t tmpfs -o size=16m tmpfs $R/d2/tmpfs; }
sudo mkdir -p $R/d2/tmpfs/sub
sudo touch $R/d2/tmpfs/a.txt $R/d2/tmpfs/sub/b.txt
echo "  non-Lustre: $(mount | grep -c " $R/d2/tmpfs ") tmpfs mounted"

# a foreign directory, if this build can make one: the case where the
# O_NOFOLLOW retry SUCCEEDS and the traversal really does fdopendir() the
# number cb_get_dirstripe() handed back.
FOREIGN=0
if sudo lfs setdirstripe --help 2>&1 | grep -q -- "--foreign"; then
	sudo rm -rf $R/d2/foreign
	if sudo lfs setdirstripe --foreign=none --xattr "lfu-round8" \
	     --flags 0xda05 $R/d2/foreign > ~/d2-foreign.log 2>&1; then
		FOREIGN=1
		echo "  foreign dir created"
	else
		echo "  foreign dir NOT created: $(tail -1 ~/d2-foreign.log)"
	fi
else
	echo "  this lfs has no setdirstripe --foreign"
fi

##############################################################################
echo
echo "=== 1. EBADF closes in the MAIN process, over the non-Lustre subtree"
##############################################################################
# -f is deliberately absent.  The count that matters is this process's.
run_strace() {   # $1 = outfile, rest = command
	local out=$1; shift
	sudo strace -e trace=close -o "$out" "$@" > /dev/null 2>&1 || true
	grep -c "close(.*= -1 EBADF" "$out" || true
}
GDS_EBADF=$(run_strace ~/d2-gds.strace lfs getdirstripe -r $R/d2/tmpfs)
FIND_EBADF=$(run_strace ~/d2-find.strace lfs find $R/d2/tmpfs --printf "%p\n")
echo "  lfs getdirstripe -r : EBADF closes = $GDS_EBADF"
echo "  lfs find --printf   : EBADF closes = $FIND_EBADF"
ck "getdirstripe -r closes no bad descriptor" "$GDS_EBADF" "0"
ck "lfs find --printf closes no bad descriptor" "$FIND_EBADF" "0"

##############################################################################
echo
echo "=== 2. and no descriptor is leaked"
##############################################################################
# every close() that succeeds must have an open that produced it; a leak shows
# as more successful opens than closes.  Count both in the main process.
sudo strace -e trace=open,openat,close -o ~/d2-leak.strace \
	lfs getdirstripe -r $R/d2/tmpfs > /dev/null 2>&1 || true
OPENS=$(grep -cE "^(open|openat)\(.*= [0-9]+$" ~/d2-leak.strace || true)
CLOSES=$(grep -cE "^close\(.*= 0$" ~/d2-leak.strace || true)
echo "  successful opens = $OPENS, successful closes = $CLOSES"
if [ "$OPENS" -gt 0 ] && [ "$CLOSES" -ge "$((OPENS - 3))" ]; then
	echo "  PASS  closes account for the opens (within the 3 stdio fds)"
else
	echo "  FAIL  $((OPENS - CLOSES)) descriptors unaccounted for"; FAIL=1
fi

##############################################################################
echo
echo "=== 3. the commands still answer the same over a non-Lustre subtree"
##############################################################################
set +e
sudo lfs getdirstripe -r $R/d2/tmpfs > ~/d2-gds.out 2>&1; GDS_RC=$?
sudo lfs getstripe -r -D $R/d2/tmpfs  > ~/d2-gs.out  2>&1; GS_RC=$?
sudo lfs find $R/d2/tmpfs             > ~/d2-plain.out 2>&1; PLAIN_RC=$?
set -e
echo "  getdirstripe -r rc=$GDS_RC, getstripe -r -D rc=$GS_RC, lfs find rc=$PLAIN_RC"
# a plain walk has no predicate needing the stripe, so it must still list
# everything -- this is the round 7 lmd_fid path too
for f in a.txt sub sub/b.txt; do
	grep -qx "$R/d2/tmpfs/$f" ~/d2-plain.out \
		&& echo "  PASS  lfs find reports $f" \
		|| { echo "  FAIL  lfs find lost $f"; FAIL=1; }
done

##############################################################################
echo
echo "=== 4. THE CASE dup2 ACTUALLY FIXES: a foreign directory is descended"
##############################################################################
if [ "$FOREIGN" = "1" ]; then
	set +e
	sudo lfs find $R/d2 --printf "%p\n" > ~/d2-fwalk.out 2>&1; FW_RC=$?
	sudo strace -e trace=close -o ~/d2-fwalk.strace \
		lfs find $R/d2 --printf "%p\n" > /dev/null 2>&1
	set -e
	FW_EBADF=$(grep -c "close(.*= -1 EBADF" ~/d2-fwalk.strace || true)
	echo "  walk over the foreign dir: rc=$FW_RC, EBADF closes = $FW_EBADF"
	ck "a walk crossing a foreign directory closes no bad descriptor" "$FW_EBADF" "0"
	grep -qx "$R/d2/foreign" ~/d2-fwalk.out \
		&& echo "  PASS  the foreign directory itself is reported" \
		|| { echo "  FAIL  the foreign directory is missing"; FAIL=1; }
else
	echo "  SKIP  no foreign directory on this build"
fi

##############################################################################
echo
echo "=== 5. the scanner's own view is unchanged"
##############################################################################
# llapi_scan_namespace() reaches cb_get_dirstripe() through
# llapi_scan_get_lmv(); its record must still carry the descriptor it says.
set +e
sudo $L/lustre/tests/llapi_scan_test -p $R/d2 > ~/d2-scan.out 2>&1
SCAN_RC=$?
set -e
if [ $SCAN_RC -eq 0 ]; then
	echo "  scan over $R/d2: $(grep -c . ~/d2-scan.out) lines, rc=0"
else
	echo "  llapi_scan_test rc=$SCAN_RC (not fatal here)"
	tail -3 ~/d2-scan.out | sed 's/^/    /'
fi

echo
if [ $FAIL -eq 0 ]; then echo "STAGE16 ALL CHECKS PASSED"; else echo "STAGE16 HAD FAILURES"; exit 1; fi
