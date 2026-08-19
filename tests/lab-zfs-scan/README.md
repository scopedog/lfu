# `tests/lab-zfs-scan/` — the ZFS backend against a real osd-zfs target

The lab that settles the ticket's acceptance list for
[`../../docs/tickets/zfs-scan-backend.md`](../../docs/tickets/zfs-scan-backend.md).
It is the ZFS half of `tests/lab-scan/`, which did the same job for ldiskfs.

**Instance:** `c3-standard-8`, Rocky 9, 120 GB boot **plus three 20 GB
persistent disks**. The extra disks are the point of difference from
`tests/lab-zfs/`: that lab put its pools on loop files, and an exported pool is
found by reading vdev labels **under `/dev`**, which is where a deployed target
lives and where the backend looks. A file-backed pool needs a search path the
upstream API does not have.

| Stage | What it does |
|---|---|
| `01-prereq.sh` | build prerequisites, OpenZFS from DKMS, and the libzpool headers the plugin needs |
| `02-build.sh` | clone master at the series' base, `git am` the eight changes, `--with-zfs --disable-ldiskfs`; asserts `scan_zfs.so` exists, links libzpool, exports all five entry points, and that `liblustreapi` links **neither** backend library |
| `03-fs.sh` | MGS+MDT and two OSTs as ZFS pools on `/dev/nvme0n2..4`, plus a client |
| `04-populate.sh` | one file per shape, including an EA too large for the SA area — the spill path with no ldiskfs equivalent — then 20k objects |
| `05-acceptance.sh` | the four acceptance items, in the order that matters |
| `06-confsanity165.sh` | conf-sanity 165 with `FSTYPE=zfs` |

## The sequencing that is the whole question

A ZFS scan reads the pool from **outside** ZFS, so the server has to let go of
it first. `05-acceptance.sh` therefore checks the refusal **before** it exports
anything: an imported pool must be refused, not read behind the kernel's back.
Then it exports, runs the contract tests, and imports again.

`conf-sanity` test_165 learned the same sequence: it calls the framework's own
`export_zpool`/`import_zpool` around the scan when `mds1_FSTYPE` is zfs, and
`stack_trap`s the import so a failure mid-test does not leave the pool with
nobody holding it. ldiskfs needs no equivalent — a block device is readable
whether or not anything has it mounted.

## Running it

Per [[lfu-gcp-lab]]: launch each stage as
`nohup bash -c "bash ~/0N-x.sh > ~/sN.log 2>&1; echo \$? > ~/sN.rc" &` and poll
for the `.rc`, because the tool's two-minute limit kills `gcloud compute ssh`
and takes the remote command with it. **`rm -f ~/sN.rc` first** — a stale rc
file reads as "finished".
