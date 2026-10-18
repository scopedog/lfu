# Remote MDT scan time split, 2026-10-17

Two GCP c3-standard-8 (us-central1-a), TCP, 23 Gb/s, MTU 1460; server
MGS+MDT+OST on loop files on pd-balanced; branch lfs-find-offload
c9903b6b15. 1,000,104 MDT objects (1M createmany -o files), one MDT,
one stream: 206 OBD_IDX_READ RPCs of 1 MiB, 206 MiB, ~208 B/record.
Harness and bpftrace scripts: tests/lab-split/. Raw log: rpc-split.txt.
Median of rounds 2-5 (round 1 cold raw was 4.24 s, an outlier).

| part | warm | cold |
|---|---|---|
| server record build (dt_index_read) | 579 ms, 72% | 5327 ms, 96% |
| server bulk send + reply | 99 ms, 12% | 126 ms, 2% |
| wire / RPC latency | 32 ms, 4% | 41 ms, 1% |
| client alloc + copy_to_user + free | 23 ms, 3% | 24 ms, 0.4% |
| library on top (decode, record, callback, startup) | 69 ms, 9% | 56 ms, 1% |
| **whole llapi_scan_mount()** | **803 ms** | **5575 ms** |

- The server record build dominates. Cold is the pd-balanced floor
  (~1 GiB of inode table at ~200 MB/s), not representative of NVMe.
- Every client-side copy together is 3% warm, 0.4% cold, ~23 ns/record.
  Zero-copy can save at most that plus part of the library's 9%.
- The path is serial: one synchronous 1 MiB RPC at a time, so the
  parts add up. Overlapping the server build with the transfer and the
  client would hide ~25% warm. Several slices in flight would use more
  than one server thread for the build, the largest share.
