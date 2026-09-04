#!/bin/bash
# A/B the device scanner across the record-size change.
#
# Alternating A,B,A,B rather than all-A-then-all-B: the VM's drift then
# falls on both arms equally.  Pinned to one CPU, and CPU time is the
# headline number -- wall clock on a 4-core VM has a ~15% spread, which is
# wider than the effect being looked for.
DEV=${DEV:-/tmp/lustre-mdt1}
N=${N:-30}
MODE=${MODE:-warm}
CPU=${CPU:-2}
B=/home/nishida/bench
OUT=$B/results/$MODE.txt
mkdir -p $B/results; : > "$OUT"

run() {
	[ "$MODE" = "cold" ] && { sync; echo 3 > /proc/sys/vm/drop_caches; }
	taskset -c "$CPU" "$B/$1/scanbench" "$DEV" 1
}

echo "=== $MODE, N=$N per arm, device=$DEV, pinned to cpu$CPU"
sync; echo 3 > /proc/sys/vm/drop_caches
for i in 1 2; do for a in pre post; do run "$a" >/dev/null 2>&1; done; done

for i in $(seq "$N"); do
	for a in pre post; do
		r=$(run "$a") || { echo "run failed: $a"; exit 1; }
		echo "$a $r" >> "$OUT"
	done
done

python3 - "$OUT" "$MODE" <<'PY'
import sys, statistics as st
rows = {}
for line in open(sys.argv[1]):
    f = line.split()
    if len(f) < 6: continue
    # arm seen emitted wall rate acc cpu
    rows.setdefault(f[0], []).append(
        dict(emit=int(f[2]), wall=float(f[3]), acc=int(f[5]), cpu=float(f[6])))
print(f"=== summary ({sys.argv[2]}) ===")
s = {}
for arm in ('pre', 'post'):
    v = rows[arm]
    cpu = sorted(x['cpu'] for x in v)
    wall = sorted(x['wall'] for x in v)
    emit = v[0]['emit']
    recsz = v[0]['acc'] // emit
    s[arm] = dict(cpu_min=cpu[0], cpu_med=st.median(cpu), wall_med=st.median(wall))
    print(f"  {arm:4s} n={len(v)} objects={emit:,} record={recsz}B")
    print(f"       CPU s : min={cpu[0]:.4f} median={st.median(cpu):.4f} "
          f"max={cpu[-1]:.4f}  spread={100*(cpu[-1]-cpu[0])/st.median(cpu):.1f}%")
    print(f"       wall s: min={wall[0]:.4f} median={st.median(wall):.4f} "
          f"max={wall[-1]:.4f}  spread={100*(wall[-1]-wall[0])/st.median(wall):.1f}%")
d_min = 100*(s['post']['cpu_min']-s['pre']['cpu_min'])/s['pre']['cpu_min']
d_med = 100*(s['post']['cpu_med']-s['pre']['cpu_med'])/s['pre']['cpu_med']
d_w  = 100*(s['post']['wall_med']-s['pre']['wall_med'])/s['pre']['wall_med']
print(f"  post vs pre, CPU min   : {d_min:+.2f}%   (positive = statx costs more)")
print(f"  post vs pre, CPU median: {d_med:+.2f}%")
print(f"  post vs pre, wall median: {d_w:+.2f}%")
ns = 1e9*(s['post']['cpu_min']-s['pre']['cpu_min'])/rows['pre'][0]['emit']
print(f"  per object: {ns:+.1f} ns")
PY
