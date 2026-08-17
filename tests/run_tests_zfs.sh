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
# 68 - 1 deleted; post-snap touch has no LMA so it is not visible
chk "live scan sees churn (67 visible)" "$(echo "$outl" | grep -c .)" 67
grep -q "LIVE dataset" /tmp/lfu_zfs_stderr.$$ \
    && ok "live-dataset warning printed" || bad "live-dataset warning missing"

# --- 5. tier-0 filters ----------------------------------------------
outf=$(scan --blocks-gt 100 "$SNAP")
chk "blocks-gt finds only big" "$(echo "$outf" | grep -c .)" 1
echo "$outf" | grep -q '0x270f' && ok "blocks-gt hit is big" || bad "wrong blocks-gt hit"

outa=$(scan --atime-older 999999 "$SNAP")
chk "atime filter excludes all" "$(echo "$outa" | grep -c .)" 0

# The lfs find spellings must compile to the same predicates as the legacy
# flags above (docs/filter-levels.md §2).
chk "--dev-blocks +100 == --blocks-gt 100" \
    "$(scan --dev-blocks +100 "$SNAP" | grep -c .)" 1
chk "--type f" "$(scan --type f "$SNAP" | grep -c .)" 66
chk "--type d finds the striped directory" \
    "$(scan --type d "$SNAP" | grep -c .)" 1
chk "--type l finds the symlink" "$(scan --type l "$SNAP" | grep -c .)" 1
chk "! --type f" "$(scan '!' --type f "$SNAP" | grep -c .)" 2

# z_pflags has no per-file compressed or encrypted bit, so those must be
# refused rather than answered "no matches" (lfu_zfs_attrs()).
"$BIN" --attrs E "$SNAP" >/dev/null 2>&1
chk "--attrs Encrypted is refused on zfs" "$?" 2
"$BIN" --attrs i "$SNAP" >/dev/null 2>&1
chk "--attrs Immutable is accepted on zfs" "$?" 0

# --- 5b. tier-1 filters, out of the one DXATTR unpack (§5.2, §6) -----
# The same predicates the ldiskfs suite checks, against byte-identical xattrs.
chk "--dev-blocks +1G matches nothing" \
    "$(scan --dev-blocks +1G "$SNAP" | grep -c .)" 0
chk "--blocks +1G finds striped1 via SOM" \
    "$(scan --blocks +1G "$SNAP" | grep -c .)" 1
chk "--size +1G finds striped1 via SOM" \
    "$(scan --size +1G "$SNAP" | grep -c .)" 1
chk "--stripe-count 2" "$(scan --stripe-count 2 "$SNAP" | grep -c .)" 1
chk "--pool fast (LOV v3)" "$(scan --pool fast "$SNAP" | grep -c .)" 1
chk "--ost 5" "$(scan --ost 5 "$SNAP" | grep -c .)" 1
chk "--ost 3,7 (a list)" "$(scan --ost 3,7 "$SNAP" | grep -c .)" 2
chk "--layout released" "$(scan --layout released "$SNAP" | grep -c .)" 1
chk "--name matches a linkea entry" \
    "$(scan --name 'report*' "$SNAP" | grep -c .)" 1
chk "--name matches the second link too" \
    "$(scan --name second_link.txt "$SNAP" | grep -c .)" 1
chk "--mdt-count 4 (striped directory)" \
    "$(scan --mdt-count 4 "$SNAP" | grep -c .)" 1
chk "--mdt-hash fnv_1a_64" "$(scan --mdt-hash fnv_1a_64 "$SNAP" | grep -c .)" 1

# --- 5c. the third outcome: undecided (§4.4) -------------------------
# striped_nosom is striped with no trusted.som, so no MDT-only scan can say
# whether it matches a size test.
scan -q --size +0 "$SNAP" >/dev/null
chk "striped, SOM-less object is undecided" "$(stat_of 'undecided')" 1
chk "-u emits it tagged" \
    "$(scan -u --size +0 "$SNAP" | grep -c '+unknown')" 1

# --- 6. internal visibility flag ------------------------------------
outi=$(scan -i "$SNAP")
chk "-i adds internals (68+2)" "$(echo "$outi" | wc -l)" 70

rm -f /tmp/lfu_zfs_stderr.$$
echo
echo "passed $pass / $((pass+fail))"
[ "$fail" = 0 ]
