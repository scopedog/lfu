# Lab — round 18, 2026-09-03

Round 18 was finished and unpushed with **nothing behavioural run**. Three
changes turn a working invocation into an error or a different answer, and
`sanity` 56El was new while 160aa had been rewritten — neither had ever run.
160aa is also the test whose `|| error` could never fire, so its green history
proved nothing.

## What was built

`~/lustre-r18` on `rhel9.7-server-mgs-mds-clone` (192.168.122.10), its own
clone — **not** `~/lustre-release`, which is somebody's working tree.

21 patches: the 18 on the rebased stack (including the two preparatory
`lustreapi.7` changes) plus 68340, 68413 and 68414, which sit under
68415–68420 on Gerrit and whose mdd/mdc fixes the changelog tests need.
Applying 68413 and 68414 on top needed two `sanity.sh` conflict resolutions —
their `160y`/`160z` land in the same region as our `160aa`–`160ad`; all six
kept.

Version, asserted three ways because two of them can lie: `config.h`
`2.17.57_64_g85f37fc`, the installed `lfs` the same, and `obdclass.ko`'s own
`modinfo` version the same — then `lctl get_param -n version` on the running
node, checked non-empty, because an empty answer is "modules not loaded" and
the framework papers over it with the userspace binary's version.

## `11-run-r18.sh` — the suite

`MDSCOUNT=2` (real DNE), `ONLY_REPEAT=2`, ldiskfs.

| Test | | |
|---|---|---|
| 56El | **new** | PASS ×2 |
| 157c | | PASS ×2 |
| 160aa | **rewritten** | PASS ×2 |
| 160ab | | PASS ×2 |
| 160ac | | PASS ×2 |
| 160ad | | PASS ×2 |
| 160y | 68413 | PASS ×2 |
| 160z | 68414 | PASS ×2 |

Zero skips. A skipped test proves nothing, which is why the runner counts them.

## `04-arms-r18.sh` — the refusals sanity does not cover

A refusal that never fires reads exactly like a pass, so each one is asserted
directly.

- **68419** a directory as a cookie is refused up front, and prints no matches
  before refusing; an empty cookie name is refused; a cookie is bound to its
  search root — accepted under its own, refused under another; two paths with
  one cookie are refused.
- **68418** `-printf %Lc/%Li/%Lo/%Lp` runs over a changelog source and over a
  plain walk; `-name` matches a file with one name; `-name g2` matches the
  hardlink and prints it under its recorded name `a/f2`.
- **68288** `--fid2path` on a mount that is not this filesystem's is refused,
  and prints no objects before refusing. Which of the two guards fires depends
  on the mount: `/tmp` is not a client mount at all, so the open refuses first.
  The `llapi_search_fsname()` comparison the round added needs a mount of
  *another* Lustre filesystem, which needs two filesystems — that is
  conf-sanity 166's case, not a single node's.

## Three fixture traps, all of them mine

Each produced a plausible wrong answer rather than an error.

1. **`--changelog` takes a required argument.** `--changelog --resolve` makes
   getopt read `--resolve` as the MDT name. Silent misparse; the error message
   then asks for the flag that was already given.
2. **DNE puts the directories elsewhere.** A plain `mkdir` lands wherever the
   balance sends it, so the MDT this arm reads holds none of the events. Reads
   as "the feature returned nothing". `lfs mkdir -i 0`, the way `sanity` uses
   `mkdir_on_mdt0`.
3. **The arms mutated their own fixture.** The cookie arms run `lfs find` over
   the log before the 68418 arms read it, and A1 stops the filesystem at the
   end, so a second run started on the wreckage of the first. The 68418 arms
   now build their own directory and register their own user; the script mounts
   the filesystem itself rather than inheriting one.

## One thing left open

`lfs find --changelog MDT --resolve -name g2` matches the hardlinked object and
prints `/mnt/lustre/.../a/f2`. The other direction, `-name f2`, matches
**nothing** — while a plain `lfs find -name f2` matches it. The surviving
record for that FID is the HLINK, which names it `g2`.

160ad asserts only the `-name g` direction, and its own comment says both
searches "have to look at the other names before dropping the object". Whether
the asymmetry is intended is not the lab's call, so the arms report it as a
NOTE and assert nothing either way.

## A public header change needs `lustre/tests` rebuilt too

`make -C lustre/utils` is the quick incremental rebuild, and it is **not
enough when a field is added to a public struct**. `llapi_scan_test` lives in
`lustre/tests/` and compiles its own `sizeof(struct llapi_scan_param)`, so a
stale binary and a fresh library disagree about the struct's length.

Round 20 hit exactly that: `sanity` 157c's test6 passes `sizeof(sp) + 8` and
expects `-EINVAL`. The stale test computed 56 + 8 = 64, the new library's
struct *is* 64 with `sp_fsname`, so the library correctly accepted it and the
test called it a failure. `make -C lustre/tests && make install` there, and it
passes twice.

Worth knowing because the failure looks like a logic regression in the very
code the round changed, and it is not.

## And the diff must be cumulative, not incremental

`git checkout -- .` in `~/lustre-r18` reverts to the committed state — the 21
patches `git am` applied — **not** to whatever the previous round left. So a
delta generated between two later branches applies onto the wrong base and
silently drops everything in between.

Round 20 hit this too: applying only the round-19→round-20 delta left a tree
with round 20's fixes and none of round 19's, and the cookie arms failed 5 of
8 with round 19's own bugs. Generate the diff from the branch the patches were
made from (`r19-backup-0903`), so it carries every round at once.

The arms caught it; a green `sanity` run alongside them did not.
