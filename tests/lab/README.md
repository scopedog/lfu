# Lab scripts — the 2026-08-17 GCP session, as it actually ran

These are the scripts that built and measured the filter work on a throwaway GCP
instance: `docs/filter-pushdown-measured-2026-08-17.md`,
`docs/warm-readahead-and-cold-2026-08-17.md` and
`docs/xiong-68020-filter-measured-2026-08-17.md` are their output. They are kept
because the next lab should not have to rediscover the shape of this one — not
because they are a polished harness. Nothing here is run by `tests/run_tests.sh`;
all of it needs root, a Lustre build tree and a mounted MDT.

Run them in order, each detached with its output to a log:

```sh
nohup bash -c "bash 01-prereq.sh > ~/s1.log 2>&1; echo \$? > ~/s1.rc" &
```

That pattern matters: an interrupted `gcloud compute ssh` takes the remote command
with it, so anything longer than a couple of minutes must survive the connection.

| script | what it does |
|---|---|
| `01-prereq.sh`, `01b.sh` | repos and build prerequisites. `01b` exists because `dnf` can claim a package is "Already downloaded" and then fail on it; `dnf clean packages` and retry |
| `02-build.sh` | clone v2_17_55, apply the six-patch stack in order, build a server, and refuse to continue unless `ENABLE_LDISKFS='yes'` is in `config.log` |
| `03b-fs.sh` | format and mount MGS+MDT+OST. `mkfs.lustre` on a loop file needs `--device-size=` in KB and will not infer it |
| `04-populate.sh` | three more OSTs, an OST pool, and one object per shape the filters need: 4-striped, 1.5 GiB, 60-way overstriped (the only object that spills to an external EA block), pooled, DoM, hardlinked, projid'd, immutable |
| `05-build-lfu.sh` | the LFU kernel harnesses and the userspace consumer; checks the evaluator symbols really are in `lfu_ring.ko` |
| `07-filters.sh`, `08-crosscheck.sh` | the filter matrix, and the same filters through both scanners with FID sets compared |
| `12-cold.sh`, `13-rawbw.sh` | the cold ritual (unmount → `drop_caches` → remount → first pass), and the raw device bandwidth that explains why every cold row came out flat |
| `20-build-theirs.sh` … `26-ours-run.sh` | LU-20591 68020 against ours: build their tree, swap module sets, run both rounds on one MDT image |

Two gotchas the scripts encode rather than explain:

- **The client mount needs an OSS up**, so format at least one OST even when only
  the MDT is being scanned.
- **`c3-standard-8` has no local SSD**, so cold is bandwidth-bound at ~183 MB/s
  and cold comparisons of anything latency-related are meaningless on it. Use a
  `-lssd` machine type for those.
