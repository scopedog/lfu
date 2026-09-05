# Batch return over llapi_scan_namespace() — 2026-09-05

Harnesses for commit `4c61e1621a LU-20603 llapi: pull a scan's records in
batches` on `statx-port-fixed` (unpushed).

- `stress.c` — the batch API against the callback API, path sets
  compared sorted: 20,221 objects, batch 1/7/100/1000/4096 × threads
  1/8, all IDENTICAL; 200 early closes without a hang. Also run under
  ASan/UBSan with leak detection: no finding in the library.
- `bench.c` — medians of 15 alternating callback/batch runs, warm,
  on a 20k-object tree under /tmp (tmpfs-class lstat, so the copy is
  at its largest share):

| threads | batch | callback | batch | delta |
|---|---|---|---|---|
| 1 | 1 | 59.0 ms | 98.6 ms | +67%, +1959 ns/obj |
| 1 | 1024 | 54.0 ms | 56.7 ms | +5.0%, +135 ns/obj |
| 4 | 1 | 18.2 ms | 100.7 ms | +455%, +4084 ns/obj |
| 4 | 1024 | 19.1 ms | 20.7 ms | +8.1%, +76 ns/obj |
| 4 | 8192 | 16.4 ms | 26.7 ms | +63%, +511 ns/obj |

The 8192 row is the per-open cost of two 4 MiB record arrays being
page-faulted in, on a tree that only fills them twice and a half; it
amortises on a large tree and is not a per-object cost.

## On the lab, against a real Lustre mount — 2026-09-05

`rhel9.7-server-mgs-mds-clone`, ldiskfs, MDSCOUNT=2 OSTCOUNT=1, module
2.17.57_64_g85f37fc. Userspace synced into `~/lustre-r18` (md5-verified
file-for-file), `liblustreapi` rebuilt and installed, symbols confirmed in
`/usr/lib64/liblustreapi.so.1.0.0` before anything was run.

- `llapi_scan_test` on `/mnt/lustre`: **14 of 14 pass**, tests 0-10 (the
  callback API, unchanged) and 11-13 (the batch API).
- `stress` on 20,021 objects: every arm **IDENTICAL** to the callback API.
  The comparison key is not just the path -- it is path, name, FID, both
  masks, size, mode, `sr_lmmsize`, `sr_lmvsize` and stripe count, so a
  field lost or mis-copied in the batch shows up as DIFFERENT.
- `stress` again on a tree carrying **1002 layouts and 1 LMV**: IDENTICAL
  in every arm. The first tree was `createmany -m`, whose objects have no
  layout at all -- so the `sr_lmm`/`sr_lmv` copies were untested until
  this run, and this is the one that exercises them.
- 200 early closes on each tree: no hang.
- `sanity` `56El 157c 160aa 160ab 160ac 160ad`: **6 PASS, 0 FAIL, 0 SKIP**.

The cost, where per-object work is an MDT ioctl rather than a cached
lstat():

| tree | threads | batch | callback | batch | delta |
|---|---|---|---|---|---|
| 20k, no layouts | 1 | 1024 | 2744.1 ms | 2755.4 ms | **+0.4%** |
| 20k, no layouts | 4 | 1024 | 938.2 ms | 951.8 ms | **+1.4%** |
| 20k, no layouts | 4 | 1 | 947.5 ms | 1114.4 ms | +17.6% |
| 1007, layouts | 4 | 1024 | 220.4 ms | 221.5 ms | +0.5% |
| 1007, layouts | 1 | 1024 | 566.1 ms | 561.5 ms | -0.8% |

So on Lustre a batch of 1024 costs under 1.5%, and on the tree whose
records carry layouts the difference is inside the run-to-run noise --
the last row is negative. The +5-8% measured off Lustre is the upper
bound it looked like: there the per-object work is a cached lstat() and
the copy is the largest share it will ever be.

A batch of 1 is the shape to avoid, at +17.6%: it pays the lock round
trip per record and removes nothing.
