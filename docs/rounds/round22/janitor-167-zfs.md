# 68288's Janitor −1: conf-sanity 167 on every ZFS config

Checked 2026-09-06. **Not resolved — instrumented**, and the earlier "resolved"
note was wrong.

## What the bot says

`Lustre Gerrit Janitor` gave Code-Review−1 on PS11:

    Newly added or changed test failed in initial testing:
    IMPORTANT: these tests appear to be new failures unique to this patch
    - conf-sanity4@zfs:test_167(Seen in reviews: 68416 68415)

and lists it failing on **21 ZFS sessions** — `conf-sanity4@zfs` plus every
`conf-sanity-special{1..10}@zfs` and `@zfs+DNE` — always as
`167(lfind --fid2path on a stopped lustre-ost1/ost1 failed)`. Every ldiskfs
session passed.

## The `--search` fix is in PS11, and it is not enough

`docs`/memory recorded this as resolved on 2026-09-03 by adding
`search="--search $(dirname $(ostvdevname 1))"`. PS11's `conf-sanity.sh`
carries that line, and the test still fails on every ZFS config. **The note
was wrong** and is corrected.

## What the CI artefacts do and do not say

From the janitor's own logs for `conf-sanity4@zfs`:

- 165, 166 and 168 all **SKIP** on ZFS (`zfs cannot be scanned while in
  service`), so **167 is the only ZFS coverage the scanner has in CI**.
- The ZFS event log shows `pool_export` at 18:51:41.9 — `export_zpool` did
  run — and the next pool event is the cleanup import 12 seconds later. The
  test failed inside that window.
- **The error text is nowhere.** test_167 redirected `lfind`'s stdout *and*
  stderr into `$got.raw`, which its own `stack_trap` deletes, so neither the
  suite log nor the test log carries a single word of why it failed.

## It passes here, on this VM

Built the lab tree with `--enable-zfs` (ZFS 2.2.11, el9.7) and ran the same
subtest against a ZFS filesystem:

    == conf-sanity test 167: lfind --fid2path names objects on a stopped OST
    offline --fid2path named 20 objects by their owner
    PASS 167 (3s)

So this is environment-dependent, and the two environments differ in at least
ZFS version (**CI 2.3.2**, here 2.2.11), distro (rocky8.10/9.6 vs el9.7) and
node layout (CI drives a separate server node through `do_facet`).

## What went in

The one thing that can be fixed without evidence: **the test now reports what
happened**. `stderr` goes to `$got.err`, kept apart from the answer in
`$got.raw`, and the failure quotes it —

    error "lfind --fid2path on stopped $ost1dev: $(cat $got.err)"

which is exactly what test_166 and test_168 already do. The next CI round will
say whether the pool could not be found, the plugin could not be loaded, or
the mount could not be reached, instead of only that it failed.

Verified: PASS 167 on ZFS here with the patched test, syntax clean, checkpatch
warnings unchanged, amended into 68288.

**No guess was applied.** Two mechanisms are plausible from here — a libzpool
2.3 difference in the import path, and `scan_zfs.so` not being reachable on
the CI node — and both are cheap to confirm once the message is in the log,
where guessing at either costs a full CI round.
