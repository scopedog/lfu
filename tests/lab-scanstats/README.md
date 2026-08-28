# lab-scanstats — the scan counters, and the two refusals

Two things the 68156 PS10 AI review found, and the controls that show each
one was real.  Run on the local server VM (`nishida@192.168.122.10`), whose
`~/lustre-160ac` is a configured build tree with an MDT on `/dev/vdb`.

Ship the series first:

```sh
git bundle create /tmp/r13.bundle lu-20650-since --not 5afbab284e^
scp /tmp/r13.bundle nishida@192.168.122.10:/tmp/
ssh nishida@192.168.122.10 'cd ~/lustre-160ac &&
    git fetch /tmp/r13.bundle "+refs/heads/lu-20650-since:refs/heads/r13" &&
    git checkout -f r13'
scp tests/lab-scanstats/* nishida@192.168.122.10:~/
```

## 10-stats-arms.sh — ss_seen counted an object twice

`ss_seen` is incremented in the pre-filter.  `LLAPI_SCAN_SKIP_XATTR` is
raised *after* the pre-filter has run, and `scan_sink_skip()` incremented
`ss_seen` again for it, so an object whose xattrs could not be read was
counted twice — exactly the torn-read case the counters exist to describe.

A quiescent device raises no such skip, so the arm that is wrong and the arm
that is right agree on it.  The lab injects the skip (every 7th object) and
then asks whether the invariant can tell them apart:

```sh
ARM=control bash ~/10-stats-arms.sh   # must FAIL
ARM=fixed   bash ~/10-stats-arms.sh   # must PASS
```

Measured 2026-08-28: control fails with `894 seen, but 0 filtered + 112
skipped + 670 classified` — 112 is the injected skips exactly — and fixed
passes.

Two things the lab had to learn the hard way, both of which make a control
pass when it should fail:

- `llapi_scan_device_test` links liblustreapi **statically** (`ldd` says
  "not a dynamic executable"), so rebuilding `lustre/utils` alone leaves the
  old `scan_sink_skip()` inside the test binary.  Relink the test.
- the plugin loader tries `PLUGIN_DIR` **before** `$LUSTRE`, so an installed
  `/usr/lib64/lustre/scan_ldiskfs.so` wins over the one just built.  Put the
  armed plugin in its place for the run.

## 11-errno-arms.sh — a build that cannot scan, and a target that was refused

`llapi_scan_device()` answered `-ENOTSUP` both for "this build has no
backend" and for "the backend is here and this libext2fs will not open the
target".  conf-sanity test_165 skips on the first, so a node carrying stock
e2fsprogs and a perfectly good MDT took the skip.

The two are now `-ENOTSUP` and `-ENOPKG`.  The lab builds a device with an
incompat feature no libext2fs knows and runs it against a build whose plugin
is installed.  Measured 2026-08-28:

```
/tmp/unsupp.img: unsupported features; needs Lustre's e2fsprogs
    ... failed: Package not installed          <- ENOPKG
no ldiskfs device scan backend: ... No such file or directory
    ... failed: Operation not supported        <- ENOTSUP
```

The ZFS half of the same split (`-EMEDIUMTYPE` for a dataset holding no ZPL
objects) is **not** covered here: this VM has no ZFS and does not build
`scan_zfs.so`.
