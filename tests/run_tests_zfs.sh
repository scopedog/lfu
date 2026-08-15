#!/bin/bash
# lfu-scan-zfs test suite. Requires root. Builds a synthetic MDT-like ZFS
# dataset (tests/mkzpool.sh), scans the snapshot, asserts classification,
# atomicity and filter behaviour.
set -u
cd "$(dirname "$0")/.."

BIN=build/lfu-scan-zfs
POOL=${LFU_TEST_POOL:-lfutest}
DS=$POOL/mdt0
SNAP=$DS@s1

pass=0 fail=0
ok()   { pass=$((pass+1)); echo "ok  $*"; }
bad()  { fail=$((fail+1)); echo "FAIL $*"; }
chk()  { local d=$1; shift; [ "$1" = "$2" ] && ok "$d" || bad "$d (got '$1' want '$2')"; }

[ "$(id -u)" = 0 ] || { echo "must run as root"; exit 2; }
[ -x "$BIN" ] || { echo "build with: make zfs"; exit 2; }

bash tests/mkzpool.sh >/dev/null

# --- mutate the live dataset AFTER the snapshot (atomicity fodder) ---
touch "/$POOL/mdt0/post_snap_file"
rm -f "/$POOL/mdt0/d0/f1"
zpool sync "$POOL"

scan() { "$BIN" "$@" 2>/tmp/lfu_zfs_stderr.$$; }
stat_of() { grep -E "$1" /tmp/lfu_zfs_stderr.$$ | grep -oE '[0-9]+' | tail -1; }

# --- 1. snapshot scan: classification counts -------------------------
out=$(scan "$SNAP")
chk "visible count"        "$(stat_of 'visible')"        62
chk "internal count"       "$(stat_of '^  internal')"    2
chk "ost-obj count"        "$(stat_of 'ost-obj')"        1
chk "agent count"          "$(stat_of 'agent')"          1
chk "bad count"            "$(stat_of 'bad')"            1
chk "sa_fail is zero"      "$(stat_of 'sa_fail')"        0
chk "emitted == visible"   "$(echo "$out" | wc -l)"      62

# --- 2. FID correctness ---------------------------------------------
want=$( (for d in 0 1 2; do for i in $(seq 0 19); do
            printf '[0x200000401:0x%x:0x0]\n' $((d*100+i)); done; done
         printf '[0x200000401:0x270f:0x0]\n'   # big  (9999)
         printf '[0x200000401:0x22b8:0x0]\n'   # sym0 (8888)
        ) | sort)
got=$(echo "$out" | awk '{print $1}' | sort)
chk "FID set exact" "$got" "$want"

# --- 3. snapshot atomicity (design §10 test 2) ----------------------
out2=$(scan "$SNAP")
chk "repeat scan bit-identical" "$out2" "$out"
echo "$out" | grep -q post_snap 2>/dev/null && bad "post-snap file leaked" \
    || ok "post-snap mutations invisible in snapshot"

# --- 4. live scan: sees mutations, warns ----------------------------
outl=$(scan "$DS")
# 62 - 1 deleted; post-snap touch has no LMA so it is not visible
chk "live scan sees churn (61 visible)" "$(echo "$outl" | grep -c .)" 61
grep -q "LIVE dataset" /tmp/lfu_zfs_stderr.$$ \
    && ok "live-dataset warning printed" || bad "live-dataset warning missing"

# --- 5. tier-0 filters ----------------------------------------------
outf=$(scan --blocks-gt 100 "$SNAP")
chk "blocks-gt finds only big" "$(echo "$outf" | grep -c .)" 1
echo "$outf" | grep -q '0x270f' && ok "blocks-gt hit is big" || bad "wrong blocks-gt hit"

outa=$(scan --atime-older 999999 "$SNAP")
chk "atime filter excludes all" "$(echo "$outa" | grep -c .)" 0

# --- 6. internal visibility flag ------------------------------------
outi=$(scan -i "$SNAP")
chk "-i adds internals (62+2)" "$(echo "$outi" | wc -l)" 64

rm -f /tmp/lfu_zfs_stderr.$$
echo
echo "passed $pass / $((pass+fail))"
[ "$fail" = 0 ]
