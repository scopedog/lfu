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
