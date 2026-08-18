# Lab scripts — LU-20603, the client-side scanner API

These build a single-node Lustre from the LU-20603 branch and check the parts
of `llapi_scan_namespace()` that a compiler cannot: does it see what `lfs find`
sees, is the answer independent of thread count, does depth limit, does a
consumer's return value reach the caller, and is the validity mask populated.

Output: [`bench-data/2026-08-18/llapi-scan-lab.txt`](../../bench-data/2026-08-18/llapi-scan-lab.txt).

Unlike `tests/lab/`, no LFU kernel patch stack is applied — this is a userspace
library addition, so the tree is otherwise stock.

Run in order, each detached, per the pattern in `tests/lab/README.md`:

```sh
rm -f ~/s1.rc                      # ALWAYS: a stale rc file reads as "done"
nohup bash -c "bash 01-prereq.sh > ~/s1.log 2>&1; echo \$? > ~/s1.rc" &
```

| script | what it does |
|---|---|
| `01-prereq.sh` | repos and build prerequisites; same as `tests/lab/` minus a stray `grep -q wc /dev/null` that could never match and killed the script under `set -e` after all the work was done |
| `02-build.sh` | clone at the base commit in `~/base.txt`, `git am` the patch, configure, build, install; refuses to continue unless `ENABLE_LDISKFS='yes'` |
| `03-fs.sh` | MGS+MDT+OST on loop files, plus the client mount. `mkfs.lustre` on a loop file needs `--device-size=` in KB |
| `04-populate.sh` | a small tree with one object per shape the record has a field for |
| `05-scantest.sh` | builds `scan_test.c` and runs the seven checks |
| `06-rebuild.sh` | re-apply and rebuild after an edit, without reformatting the images |

Three things these encode rather than explain:

- **Delete the `.rc` file before every launch.** A stale one from the previous
  run reads as "finished" and you will report the last run's exit code while
  this run is still compiling. It cost a full rebuild here.
- **Do not guard configure on `[ -f Makefile ]`** — lustre-release *tracks* a
  top-level `Makefile`, so it survives `git clean -fdx` while every generated
  sub-Makefile does not, and the build then fails with "No targets specified".
  `config.status` is the honest witness.
- **Unmount everything before `make install`**, or it dies on a busy
  `/sbin/mount.lustre` after a successful build. `06-rebuild.sh` unmounts, then
  remounts the same images so a populated tree survives an edit.
