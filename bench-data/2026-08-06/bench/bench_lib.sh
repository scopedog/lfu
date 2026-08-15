#!/bin/bash
# LFU K4 benchmark runners — deployed to MDS:/tmp/bench/. Run as root.
# Usage:
#   bench_lib.sh a_run  <tag>   — Procedure A: one cold-cache OI scrub, wait, save results
#   bench_lib.sh b_run  <tag>   — Procedure B: one cold-cache lfu-scan-ldiskfs run
#   bench_lib.sh load_start     — start createmany/unlinkmany loop on local client mount
#   bench_lib.sh load_stop
set -u
MDT=benchfs-MDT0000
DEV=/dev/vdd
SCAN=/tmp/lfu/build/lfu-scan-ldiskfs
CM=/usr/lib64/lustre/tests/createmany
UM=/usr/lib64/lustre/tests/unlinkmany
LOADDIR=/mnt/benchfs/load
OUT=/tmp/bench

cold() { sync; echo 3 > /proc/sys/vm/drop_caches; }

iostat_start() { nohup iostat -x 10 vdd > "$OUT/$1.iostat" 2>&1 & echo $! > "$OUT/$1.iostat.pid"; }
iostat_stop()  { kill "$(cat "$OUT/$1.iostat.pid")" 2>/dev/null; rm -f "$OUT/$1.iostat.pid"; }

a_run() {
    local tag=$1
    mkdir -p "$OUT"
    cold
    iostat_start "a_$tag"
    lctl lfsck_start -M $MDT -t scrub -r -s 0 || { iostat_stop "a_$tag"; return 1; }
    local t0=$(date +%s)
    while :; do
        local s=$(lctl get_param -n osd-ldiskfs.$MDT.oi_scrub)
        local st=$(awk '/^status:/{print $2}' <<<"$s")
        awk '/^(status|checked|run_time|average_speed|real_time_speed|current_position)/' <<<"$s" \
            | sed "s/^/t=$(( $(date +%s) - t0 )) /" >> "$OUT/a_$tag.samples"
        [ "$st" = completed ] && break
        [ $(( $(date +%s) - t0 )) -gt 3600 ] && { echo TIMEOUT >> "$OUT/a_$tag.samples"; break; }
        sleep 10
    done
    lctl get_param -n osd-ldiskfs.$MDT.oi_scrub > "$OUT/a_$tag.final"
    iostat_stop "a_$tag"
    echo "A[$tag] done"
}

b_run() {
    local tag=$1
    mkdir -p "$OUT"
    cold
    iostat_start "b_$tag"
    /usr/bin/time -v "$SCAN" -q "$DEV" > "$OUT/b_$tag.out" 2>&1
    iostat_stop "b_$tag"
    echo "B[$tag] done"
}

load_start() {
    mkdir -p "$LOADDIR" "$OUT"
    rm -f /tmp/STOP_LOAD
    nohup bash -c '
        i=0
        while [ ! -f /tmp/STOP_LOAD ]; do
            '"$CM"' -m '"$LOADDIR"'/l$i- 20000 2>&1 | grep "ops/second"
            '"$UM"' '"$LOADDIR"'/l$i- 20000 > /dev/null 2>&1
            i=$((i+1))
        done' >> "$OUT/load.log" 2>&1 &
    echo $! > "$OUT/load.pid"
    echo "load started"
}

load_stop() {
    touch /tmp/STOP_LOAD
    sleep 2
    echo "load stopped; recent rates:"
    tail -5 "$OUT/load.log"
}

"$@"
