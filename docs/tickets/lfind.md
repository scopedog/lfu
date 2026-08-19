# LU-XXXXX: `lfind(8)`, a server-side find over a target scan

**Not yet filed.** Technical task, parent **LU-20462**, related to **LU-20606**
(the scanner it consumes) and **LU-20605** (the front half of the split it
finishes). **Components: utils.**

Design of record: [`design-llapi-scan-device.md`](../design-llapi-scan-device.md) §9.

**Why not under LU-20606.** That ticket's *In scope* is the module — enumeration,
FID recovery, attribute extraction *"driven by a caller-supplied mask"*, filter
pushdown, parallel scan, checkpoint and restart. A command is a caller, not the
module. It is the same split LU-20603 made for the same reason, in its own
words: *"Its own ticket because the scanner has several queued consumers … and
each should be landable on its own."* Two of the four changes here also touch
`lfs` and the namespace side of `liblustreapi`, whose proof is `sanity` 56\* and
has nothing to do with scanning a device.

---

## Summary

utils: lfind, server-side find over a target scan

## Description

`lfind(8)` is a **server-side command**: it runs on the MDS or OSS whose disks
hold the target, and the server package alone installs it. A client has no
target to read, and `lfs find` remains the command there.

It runs `lfs find`'s predicates against a target's own objects, read off the
device through `llapi_scan_device()` (LU-20606) — no mount, no MDS process, no
client, so a snapshot or a failover partner's LUN scans like a serving target.
Reading the device exposes every object's metadata with none of the access
control a mount applies, so it is root-only and belongs in `sbin`.

**Not a mode on `lfs find`.** That is a client command by construction:
`llapi_is_lustre_mnt()` requires `":/"` in the mount's device name, so a server
target mount is not recognised and `lfs find` answers `-ENODEV` there. `lfs`
also ships in `lustre-client`, where the scan backend does not, so the flag
would answer `-ENOTSUP` on every client.

**One vocabulary, not two.** The option table and its parse loop move out of
`lfs_find()` into a file compiled into both programs, as `callvpe.c` already
is. Nothing new is exported and no ABI is touched.

**What differs, and `lfind(8)` documents:**
- It prints FIDs: a target holds names and parent FIDs, not paths. `--name`
  matches any name in the link xattr; `-printf` is refused.
- One invocation covers one target, which under DNE is part of a namespace and
  not all of it. `--local` closes that for one node.
- `--size` and `--blocks` are size-on-MDT's answer or none, since a scan cannot
  glimpse. An object nothing can settle is reported undecided, not as a miss.
- `--ost`, `--mdt` and `--xattr` need the mounted filesystem and are refused
  before the scan, because afterwards "no matches" and "cannot answer" look
  alike.

**Naming the target:** `--device` always works; `--target NAME` resolves through
`osd-ldiskfs.<name>.mntdev`, which exists only while it is mounted here;
`--local` takes every target the node serves, skipping the MGS.

**Acceptance:** `sanity.sh` 56\* stays green — the proof that moving the parser
and splitting `cb_find_init()` changed nothing — and conf-sanity test_165 diffs
`lfind --type f` against what the client saw on a stopped filesystem.

**Four changes**, stacked on LU-20606's:

| | Change | Proof |
|---|---|---|
| 1 | `llapi: split the deciding half out of cb_find_init` | `sanity` 56\* |
| 2 | `lfs: share find's predicate parsing` | `sanity` 56\* |
| 3 | `llapi: run find's predicates over a device scan` | conf-sanity test_165 |
| 4 | `utils: lfind, find over a scan of a target` | conf-sanity test_165 |

---

## Two things to settle before filing

**The name.** glibc has `lfind(3)` — a linear-search function on the
`lsearch(3)` page — so `man lfind` finds that one and ours needs `man 8 lfind`.
The prototype, its man page and every document in this project say `lfind`,
which is why it stands; `lfsscan` is the obvious alternative and a reviewer
objecting has a fair point. Filing makes the name public, so decide first.

**A bug to file separately.** The refactor uncovered it: `lfs find` prints its
error and **exits 0** after a bad `--comp-flags` or `--mirror-state`, because
those failures jump to the cleanup without setting `ret`. Change 2 preserves
that behaviour deliberately — fixing it changes what the command returns and
belongs in its own patch against `lfs`.

---

## Paste into Jira (wiki markup)

Jira renders wiki markup, not Markdown: {{{{monospace}}}} replaces backticks,
and a line *starting* with an asterisk becomes a bullet, so a bold lead-in uses
an {{h5.}} heading instead.

```
{{lfind(8)}} is a server-side command: it runs on the MDS or OSS whose
disks hold the target, and the server package alone installs it.  A client
has no target to read, and {{lfs find}} remains the command there.

It runs {{lfs find}}'s predicates against a target's own objects, read off
the device through {{llapi_scan_device()}} (LU-20606) -- no mount, no MDS
process, no client, so a snapshot or a failover partner's LUN scans like a
serving target.  Reading the device exposes every object's metadata with
none of the access control a mount applies, so it is root-only and belongs
in sbin.

h5. Not a mode on lfs find
That is a client command by construction: {{llapi_is_lustre_mnt()}}
requires ":/" in the mount's device name, so a server target mount is not
recognised and {{lfs find}} answers -ENODEV there.  {{lfs}} also ships in
lustre-client, where the scan backend does not, so the flag would answer
-ENOTSUP on every client.

h5. One vocabulary, not two
The option table and its parse loop move out of {{lfs_find()}} into a file
compiled into both programs, as {{callvpe.c}} already is.  Nothing new is
exported and no ABI is touched.

h5. What differs, and lfind(8) documents
- It prints FIDs: a target holds names and parent FIDs, not paths.
{{--name}} matches any name in the link xattr; {{-printf}} is refused.
- One invocation covers one target, which under DNE is part of a namespace
and not all of it.  {{--local}} closes that for one node.
- {{--size}} and {{--blocks}} are size-on-MDT's answer or none, since a
scan cannot glimpse.  An object nothing can settle is reported undecided,
not as a miss.
- {{--ost}}, {{--mdt}} and {{--xattr}} need the mounted filesystem and are
refused before the scan, because afterwards "no matches" and "cannot
answer" look alike.

h5. Naming the target
{{--device}} always works; {{--target NAME}} resolves through
{{osd-ldiskfs.<name>.mntdev}}, which exists only while it is mounted here;
{{--local}} takes every target the node serves, skipping the MGS.

h5. Acceptance
{{sanity.sh}} 56* stays green -- the proof that moving the parser and
splitting {{cb_find_init()}} changed nothing -- and conf-sanity test_165
diffs {{lfind --type f}} against what the client saw on a stopped
filesystem.
```
