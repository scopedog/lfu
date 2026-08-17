# Lab scripts — the ZFS tier-1 session

`tests/lab/` is the ldiskfs filter lab of 2026-08-17. These are its ZFS
counterpart: the run that builds and exercises `rec(DORA_XATTR)` on **osd-zfs**,
where tier 1 was refused until the iterator was made to keep the SA xattr
nvlist it already unpacks.

Same detached-and-poll discipline, for the same reason (an interrupted
`gcloud compute ssh` takes the remote command with it):

```sh
nohup bash -c "bash 01-prereq.sh > ~/s1.log 2>&1; echo \$? > ~/s1.rc" &
```

| script | what it does |
|---|---|
| `01-prereq.sh` | build prerequisites and OpenZFS from DKMS; refuses to continue without both `/usr/src/zfs-*` and the DKMS object dir for the running kernel |
| `02-build.sh` | v2_17_55 + the six-patch stack, `--with-zfs --disable-ldiskfs`. `--with-zfs` must be **bare** — a path makes configure look for `<path>/$LINUXRELEASE`. Greps `ENABLE_ZFS='yes'` out of `config.log`, since configure exits 0 either way, and then checks `osd_otable_it_xattr` is really in `osd_zfs.ko` |
| `03-fs.sh` | three loopback zpools, MGS+MDT+2 OSTs+client. Dataset names are fixed by hand rather than left to `llmount.sh`, because stage 8 has to name the MDT dataset to the userspace scanner |
| `04-populate.sh` | one object per shape a tier-1 predicate needs — 1.5 GiB striped (SOM), pooled, hardlinked (linkea), projid, immutable, plus a deliberately oversized xattr to provoke the xattr-directory path — and 100k for volume |
| `05-build-lfu.sh` | `lfu_ring.ko`, `lfind-kmdt`, and `lfind-zfs` against the DKMS source |
| `07-filters.sh` | the filter matrix on a **mounted, serving** ZFS MDT. Its first line is the point of the run: the module's tier-1 advertisement, which read `none` before this work |
| `08-crosscheck.sh` | both evaluators on the same data. One script because the sequencing is forced: the kernel scanner needs the target mounted, the userspace one needs the pool exported, so it runs every filter through the kernel, takes the filesystem down, replays them through `lfind-zfs`, and brings it back up |
| `09-rates.sh` | warm rates, medians of three: no filter, a rejecting tier-0 filter, a tier-1 filter |
