# LU-20611: `lfind(8)`, the find command for a Lustre target

**Filed 2026-08-19 as LU-20611** — Technical task, Open, parent **LU-20462**.
The four commits are tagged to it.

**Three things to fix on the ticket:**

- **The description renders wrong twice over.** Every one of the 26 `{{...}}`
  monospace markers was stored escaped as `\{{` or `{\{`, so the page shows
  literal braces and backslashes; and the option names are **struck through**,
  because `-x-` is strikethrough in Jira's markup and `--uid, --mtime, ... --`
  is a run of hyphen pairs. Replace it with the block at the end of this file,
  which has no hyphen pair, asterisk or brace outside a `{code}` block.
- **Assignee is WC Triage**, not you.
- There is no link to
  **LU-20606** (the scanner it consumes) or **LU-20605** (the front half of the
  split it finishes) — only the LU-20462 parent.

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

## Paste into Jira

**What is actually happening:** the description is going through Atlassian's
rich-text editor, which autoformats *markdown* as you paste. That explains all
three manglings at once — `{{x}}` became inline code (stored as `\{{`), `--x--`
became strikethrough, `--` became an en dash, and `h5.` became a real heading.
It is not Jira wiki markup misfiring.

So the block below is written for that editor: no `--` outside the code fence,
no asterisks, no braces, and triple backticks for the one place option names
have to appear literally. Paste it whole; if the fence does not turn into a
code block, select those three lines and press the code button.

**LU-20611's description is currently the older block** and shows the damage
(`-device-device`, en dashes). Replace it with this.

~~~
lfind(8) is find for a Lustre target: it answers the questions lfs find
answers, about uid, mtime, size, type and project id, by reading a
target's own objects off the device rather than walking a mounted
namespace.

h5. Where it runs
On the MDS or OSS holding the target, and only there: the server package
alone installs it, and a Lustre client has no target to read. It needs no
mount, no MDS process and no client, so a snapshot or a failover partner's
LUN scans like a serving one. It is root only, because reading the device
bypasses every access control a mount applies. The objects come from
llapi_scan_device() (LU-20606).

h5. Naming the target
```
lfind --device /dev/vdb --uid 1000 --mtime +30
lfind --target testfs-MDT0000 --type f --size +1G
lfind --local --projid 1999
```
A device always works, and needs nothing mounted. A target name resolves
through osd-ldiskfs.NAME.mntdev, which exists only while that target is
mounted here. The local form takes every target the node serves, skipping
the MGS, and reports a target that fails without ending the sweep.

h5. Not a mode on lfs find
That is a client command by construction: llapi_is_lustre_mnt() requires
":/" in the mount's device name, so a server target mount is not
recognised and lfs find answers ENODEV there. lfs also ships in
lustre-client, where the scan backend does not. The predicates are shared
rather than copied: the option table and its parse loop move out of
lfs_find() into a file compiled into both programs, as callvpe.c is. No
new export, no ABI change.

h5. What differs, documented in lfind(8)
It prints FIDs, a target having names and parent FIDs but no paths, so a
name match reads the link xattr and printf formats are refused. One
invocation covers one target, which under DNE is part of a namespace and
not all of it. Size and blocks are size on MDT's answer or none, since a
scan cannot glimpse, and an object nothing can settle is reported
undecided. The ost, mdt and xattr predicates need the mounted filesystem
and are refused before the scan starts.

h5. Acceptance
The 56 series in sanity.sh stays green, which is the proof that moving the
parser and splitting cb_find_init() changed nothing, and conf-sanity
test_165 diffs a regular file scan against what the client saw on a
stopped filesystem.
~~~
