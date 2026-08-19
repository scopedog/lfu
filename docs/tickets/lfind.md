# LU-XXXXX: `lfind(8)`, the find command for a Lustre target

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

utils: lfind, the find command for a Lustre target

## Description

`lfind(8)` is `find` for a Lustre target: the predicates `lfs find` takes —
`--uid`, `--mtime`, `--size`, `--type`, `--projid` — answered by reading a
target's own objects off the device rather than walking a mounted namespace.

It is a **server command**, run on the MDS or OSS holding the target, named
with `--device`, `--target NAME` or `--local`. No mount, no MDS process and no
client, so a snapshot or a failover partner's LUN scans like a serving one;
root-only, because reading the device bypasses every access control a mount
applies. The objects come from `llapi_scan_device()` (LU-20606).

**Not a mode on `lfs find`:** that is a client command by construction —
`llapi_is_lustre_mnt()` requires `":/"` in the mount's device name, so it
answers `-ENODEV` on a server — and `lfs` ships in `lustre-client`, where the
scan backend does not. The predicates are shared rather than copied: the option
table and its parse loop move out of `lfs_find()` into a file compiled into
both programs, as `callvpe.c` is. No new export, no ABI change.

**What differs**, documented in `lfind(8)`: it prints FIDs, a target having
names and parent FIDs but no paths, so `--name` matches any name in the link
xattr and `-printf` is refused; one invocation covers one target, which under
DNE is part of a namespace; `--size` and `--blocks` are size-on-MDT's answer or
none, since a scan cannot glimpse, and an object nothing can settle is reported
undecided; `--ost`, `--mdt` and `--xattr` need the mounted filesystem and are
refused before the scan starts.

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
{{lfind(8)}} is {{find}} for a Lustre target: the predicates {{lfs find}}
takes -- {{--uid}}, {{--mtime}}, {{--size}}, {{--type}}, {{--projid}} --
answered by reading a target's own objects off the device rather than
walking a mounted namespace.

It is a server command, run on the MDS or OSS holding the target, named
with {{--device}}, {{--target NAME}} or {{--local}}.  No mount, no MDS
process and no client, so a snapshot or a failover partner's LUN scans like
a serving one; root-only, because reading the device bypasses every access
control a mount applies.  The objects come from {{llapi_scan_device()}}
(LU-20606).

h5. Not a mode on lfs find
That is a client command by construction -- {{llapi_is_lustre_mnt()}}
requires ":/" in the mount's device name, so it answers -ENODEV on a server
-- and {{lfs}} ships in lustre-client, where the scan backend does not.  The
predicates are shared rather than copied: the option table and its parse
loop move out of {{lfs_find()}} into a file compiled into both programs, as
{{callvpe.c}} is.  No new export, no ABI change.

h5. What differs, documented in lfind(8)
It prints FIDs, a target having names and parent FIDs but no paths, so
{{--name}} matches any name in the link xattr and {{-printf}} is refused;
one invocation covers one target, which under DNE is part of a namespace;
{{--size}} and {{--blocks}} are size-on-MDT's answer or none, since a scan
cannot glimpse, and an object nothing can settle is reported undecided;
{{--ost}}, {{--mdt}} and {{--xattr}} need the mounted filesystem and are
refused before the scan starts.

h5. Acceptance
{{sanity.sh}} 56* stays green -- the proof that moving the parser and
splitting {{cb_find_init()}} changed nothing -- and conf-sanity test_165
diffs {{lfind --type f}} against what the client saw on a stopped
filesystem.
```
