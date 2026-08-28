# lab-hardlink — `--since` and a file with two names

68417 PS2's AI review asked whether `--since` can lose a hardlinked file.
It could.

`llapi_scan_fid()` resolves a FID with linkno 0, which is the first linkea
entry — the name the file was created under. `find_since_rec_cb()` tested the
subtree against that one name, so with `/a/f` and `/b/g` the same inode,
`lfs find /b --since 2h` was answered about `a/f`, decided it was not under
`/b`, and dropped the file. A walk of `/b` prints `b/g`. `-name` had the same
shape: it saw one basename where a walk sees each. `find_device_prefilter()`
already walks every linkea name for exactly this reason.

The fix walks the links here too — `llapi_fid2path_at()` once per link — and
only for a file whose link count says it has another name, so nothing else
pays for it. sanity `160ad` is the case.

## Running it

Ship the series to the lab VM, then:

```sh
scp tests/lab-hardlink/* nishida@192.168.122.10:~/
ssh nishida@192.168.122.10 'sudo -n ARM=fixed   ONLY_REPEAT=2 bash ~/12-160ad-arms.sh'
ssh nishida@192.168.122.10 'sudo -n ARM=control ONLY_REPEAT=1 bash ~/12-160ad-arms.sh'
```

`ARM=control` cuts the link enumeration back out of `find_since_pick()`.

## Results, 2026-08-28

| arm | 160aa | 160ab | 160ac | 160ad |
|---|---|---|---|---|
| fixed (x2) | PASS | PASS | PASS | PASS |
| control | PASS | PASS | PASS | **FAIL** |

The control fails with

```
sanity test_160ad: @@@@@@ FAIL: --since under d160ad.sanity/b lost the hardlinked file
```

which is the whole point: the file exists, a walk finds it, and `--since`
did not. SKIP was 0 everywhere.

## `ARM=nofid` — the object `--changelog` exists to report

68420 PS2's AI review noticed that nothing exercised the two things that
separate `--changelog` from `--since`: an object unlinked since its event is
still in the answer, and its FID names it once no pathname does. Writing the
case found the second half missing.

`find_decide()` resolves a FID through the mount for a target scan too, and
there an object with no pathname is **counted, not printed** — the target's
own objects never had a name. `--changelog` took the same branch, so an
unlinked object was counted as "no pathname" and the one thing `--since`
cannot report came back silently absent, while `lfs-find.1` said it would be
named. `fc_fid_when_lost` now separates the two sources.

```sh
ssh nishida@192.168.122.10 'sudo -n ARM=nofid ONLY=160ab bash ~/12-160ad-arms.sh'
```

Measured 2026-08-28: the control fails with

```
sanity test_160ab: @@@@@@ FAIL: --changelog did not name the unlinked [0x200000402:0x7:0x0]
```

and the fixed arm passes 160aa/ab/ac/ad twice each, SKIP 0.

## Two things the runner has to get right

- `sudo` sets `HOME=/root`, so `$HOME/lustre-160ac` is not the tree. The
  path is spelled out, as `09-bisect-build.sh` does.
- `llmount.sh` formats and `sanity.sh`'s own setup does not, so a stale
  `/tmp/lustre-mdt*` device file carries a stale changelog index into the
  next run. They are removed before every arm.
