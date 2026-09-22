# Staged Gerrit replies — post with the push, not before

Each file is a `gc batch` payload. Post after the patchset carrying the
fixes is up, so a reviewer opening the thread finds the change in the
current revision rather than a "Done." against a revision without it. That
is the order batch 1 used.

    gc batch <change> docs/rounds/b2-0922/replies/<change>.json --dry-run
    gc batch <change> docs/rounds/b2-0922/replies/<change>.json

## 68288 — five threads from 2026-09-11 (PS14), all already fixed

Each was checked against the tree before the reply was written, not assumed:

| thread | why "Done." is true |
|---|---|
| `/COMMIT_MSG:45` | none of the stranded words survives -- "dropped,", the two stray "is", "being", the `302 both exercise` line |
| `llapi_scan_rec_path.3:58` | the entry now reads "in this set only when no file owns it: a precreated object that has never been written carries no owner FID" |
| `lustreapi.h:625` | `CLASS` 1<<46, `LMV_SHARD` 1<<47, `OWNER` 1<<48 -- no holes |
| `pfind.c:3883` **(defect)** | `fds_dirmap_built` / `pp_ran`, set where the pre-pass sweeps |
| `pfind.c:3942` | `char mfs[PATH_MAX]` |

The dry run resolves all five to the right threads.

## Still owed, not staged

**68160, Andreas on PS20** -- the libblkid/`--label` suggestion, raised
three times and never answered. It wants a new dependency nothing in the
tree links today, so deferring is reasonable, but the thread should say so
rather than stay open. Wording is the user's call, since it declines a
maintainer's suggestion.

**The 09-22 AI round's 24** are answered by code rather than by replies;
they can be marked resolved when that patchset goes up.
