#!/bin/bash
# Run Lustre's OWN test suites against osd-zfs, to answer a question our lab
# scripts cannot: does the LFU patch stack break anything upstream expects?
#
# Everything so far has tested the feature we added.  This tests the code we
# touched -- osd-zfs/osd_scrub.c is the scrub's own file, and the patch
# refactors __osd_xattr_load_by_oid(), which the *normal* scrub path calls.
#
#   bash 10-suite.sh <label>       label goes in the result filenames
#
# Run it once on the patched build and once on a clean v2_17_55 (11-swap.sh),
# because these suites have known failures on ZFS: a failure only means
# something if it is not also in the baseline.
set -u
LABEL="${1:?usage: 10-suite.sh <label>}"
cd ~/lustre-release/lustre/tests || exit 1

# bash, never sh: stack_trap() in test-framework.sh parses `trap -p` output and
# breaks in POSIX mode (zfs-mdt-verification-2026-08-07.md §1).
export FSTYPE=zfs
export SLOW=no
export NAME=local
# single all-in-one node
export mds_HOST=$(hostname) ost_HOST=$(hostname) CLIENTS=""
export MDSCOUNT=1 OSTCOUNT=2
export MDSSIZE=2097152 OSTSIZE=2097152

echo "=== FSTYPE=$FSTYPE  label=$LABEL  $(date -u +%FT%TZ) ==="
echo "=== lustre: $(cat ~/lustre-release/lustre/include/lustre_ver.h 2>/dev/null | grep -m1 LUSTRE_VERSION_STRING || echo '?') ==="

run_suite() {
	local suite="$1"; shift
	local log=~/suite-$LABEL-$suite.log
	echo "--- $suite (${*:-full}) ---"
	timeout 5400 bash "$suite".sh > "$log" 2>&1
	local rc=$?
	# the framework's own summary lines
	local pass=$(grep -c "^PASS " "$log")
	local fail=$(grep -cE "^(FAIL|ERROR) " "$log")
	local skip=$(grep -c "SKIP" "$log")
	printf '%-16s rc=%-3s pass=%-4s fail=%-3s skip=%s\n' "$suite" "$rc" "$pass" "$fail" "$skip"
	if [ "$fail" != 0 ]; then
		echo "    failing tests:"
		grep -E "^(FAIL|ERROR) " "$log" | sed 's/^/      /' | head -20
	fi
}

# sanity.sh refuses to start without a non-root test user: check_runas_id()
# wants RUNAS_ID (default 500) to exist on both MDS and client.  On a
# single-node lab that is one useradd, and without it the whole suite aborts at
# setup with zero tests run -- which is not a result about our patch.
# ...and it must be able to REACH the build tree.  The suites exec binaries out
# of $LUSTRE/utils and $LUSTRE/tests, so a 0700 home directory makes every
# non-root test fail with "execvp fails ... (13): Permission denied" -- which
# looks like a Lustre failure and is not one.  Four sanity tests (27Ke, 27W,
# 102c, 102j) fail exactly this way without the traverse bit.
chmod o+x "$HOME" 2>/dev/null || true

if ! id -u 500 >/dev/null 2>&1; then
	groupadd -g 500 runas 2>/dev/null || true
	useradd -u 500 -g 500 -M -s /sbin/nologin runas 2>/dev/null || true
	echo "created uid/gid 500: $(id 500 2>&1)"
else
	echo "uid 500 already exists: $(id -nu 500)"
fi

echo "=== formatting and mounting (llmount.sh) ==="
bash llmount.sh > ~/llmount-$LABEL.log 2>&1
rc=$?
echo "llmount rc=$rc"
if [ $rc -ne 0 ]; then tail -30 ~/llmount-$LABEL.log; exit 1; fi
lctl dl | head

echo
echo "=== suites ==="
SUITES="${SUITES:-sanity-scrub sanity conf-sanity}"
for suite in $SUITES; do
	case "$suite" in
	# sanity-scrub is the one that matters: it drives OI scrub through the
	# very iterator and xattr-load path the patch touches.
	sanity-scrub) run_suite sanity-scrub ;;
	# a metadata/xattr slice of sanity: the attributes the patch reads
	sanity)       ONLY="24 27 33 39 102 103" run_suite sanity ;;
	# does the OSD still come up and down cleanly
	conf-sanity)  ONLY="0 1 5 32" run_suite conf-sanity ;;
	esac
done

echo
echo "=== dmesg: anything alarming ==="
# NOT -i "BUG": every test banner is a "Lustre: DEBUG MARKER" line and DEBUG
# contains BUG, so the old pattern reported the whole run as alarming.
d=$(dmesg | grep -E "kernel BUG|WARNING:|Call Trace|general protection|NULL pointer|slab corruption|list_add corruption" | tail -15)
[ -n "$d" ] && echo "$d" || echo "  (clean)"
echo "SUITE-$LABEL DONE"
