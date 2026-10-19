# pfind-wait lab, 2026-10-18

Fix: `~/lfs-pfindwait-1018`, branch `lu-pfind-wait`, commit 26541758217d
(on master-1014 ee61b3f6dd). The VM arm was built from 18be8e2356, which
has the same tree. Only the commit message changed after that.

## Setup

- VM `rhel9.7-server-mgs-mds-clone` (4 vCPU). Another agent had it until
  16:57 and shut it down. I started it at 17:06 and shut it down at 17:23.
- Arms: `m` = stock master-1014 (`/tmp/lab1018-m`, built earlier today by
  01-build.sh), `pw` = the fix (`/tmp/lab1018-pw`, same recipe,
  `tests/lab-1018/pw-build.result.txt`). They really differ: `m`
  imports `sched_yield` and has 1 call to `pthread_cond_wait`; `pw` has 0
  and 2.
- One `lfs` binary (m's). The arm is picked with `LD_PRELOAD`, and every timed
  run logs the `liblustreapi` path from `/proc/<pid>/maps`.
- Fixture: `FSNAME=lfst MDSCOUNT=2 OSTCOUNT=2 MDSSIZE=800000`, 100 dirs x
  1000 mknod files, built once per script run.
- Script: `tests/lab-1018/pw-bench.sh`. Results:
  `pw-bench-typef.result.txt`, `pw-bench-mtime.result.txt`.
- Arms alternate m, pw, m, pw, after one warm-up each. Each pair has a `run`
  sample (wall time, plus main-thread utime+stime polled from
  `/proc/<pid>/task/<pid>/stat` every 20 ms) and a `/usr/bin/time`
  sample (process user+sys). "cold" clears the mdc lock LRU first.

## Results

`lfs find D --threads 4 -mtime -1` stats every file. 5 pairs per mode:

| mode | arm | wall (time) | process CPU | main thread CPU |
|---|---|---|---|---|
| cold | stock | 4.83 [4.75-4.87] | 4.69 [4.43-4.79] | 1.91 [1.86-2.10] |
| cold | fixed | 4.08 [3.99-4.17] | 3.26 [3.25-3.37] | 0.00 |
| warm | stock | 4.86 [4.74-4.90] | 4.62 [4.57-4.72] | 1.88 [1.71-2.05] |
| warm | fixed | 4.28 [3.98-4.39] | 2.87 [2.78-3.20] | 0.00 |

Paired fixed minus stock: CPU -1.18 to -1.94 s and wall -0.51 to -0.79 s.
All 10 pairs moved the same way. The spread within one arm is about 0.1 to
0.4 s, so these gaps are well above the noise.

`lfs find D --threads 4 -type f` is answered from readdir, so the walk is
short. 6 pairs per mode:

| mode | arm | wall | process CPU | main thread CPU |
|---|---|---|---|---|
| cold | stock | 0.23 | 0.55 | 0.20 (of 0.26 wall) |
| cold | fixed | 0.24 | 0.34 | 0.00 |
| warm | stock | 0.22 | 0.51 | 0.20 |
| warm | fixed | 0.23 | 0.37 | 0.00 |

Here wall time does not change (within +-0.03 s). CPU drops 0.09 to 0.25 s in
every pair.

Answers were identical in every run: 100101 lines for `-mtime -1` and 100000
for `-type f`, with the same sorted md5 in both arms. `--threads 1` gives
100000 too.

Notes:
- On this node the spinner gets only about 40% of a core in the `-mtime` runs.
  It competes with 4 workers and the local MDS for 4 vCPUs. That is also why
  wall time gets worse. On a client with a remote MDS we expect it to take a
  whole core (not measured).
- In the `-mtime` runs, wall time from `run` (4.7 to 4.8 s in both arms) is
  higher than wall time from `/usr/bin/time`. The 20 ms awk poller costs CPU
  on a full node. Trust the `/usr/bin/time` wall times.

## Shutdown path

`LLAPI_FAIL_LOC=LLAPI_FAIL_PFIND_SEM`, `--threads 4`, `timeout 120`. 10
runs per arm, alternated. Every run gave rc=5 and "lfs: failed for
'/mnt/lfst/pw': Input/output error" in 0.06 s, so there was no hang (rc 124
would mean a timeout). The runs end before the 50 ms maps sample, so these 20
runs have no maps proof. They use the same `LD_PRELOAD` as the proven runs.

## Hang probe (fixed arm)

50 finds of one 1000-file dir at each of `--threads` 2, 4, 8 and 16, with
`timeout 30`. All 200 exited 0.

## Sanity

`02-sanity.sh pw pw pw-56 "56"`, with lfs bind-mounted and its maps showing
`/tmp/arm1018pw/lib/liblustreapi.so.1.0.0` (md5 af701aa8c011 = the pw
build). Result: 87 PASS, 0 FAIL, 1 SKIP (56xc: needs 2 GB free).
56Ek, the `LLAPI_FAIL_PFIND_SEM` test, passed. Result file:
`tests/lab-1018/pw-sanity56.result.txt`. Every `lfs find` in 56* runs through
`parallel_find()`, because the default thread count is at least 4.
