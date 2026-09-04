# The Gerrit AI's new round (2026-09-04) and lreview on 68157

Seven comments arrived on the **current** patchsets — PS16/PS17, not the
PS1 backlog — so a much higher proportion are live.

## 68095 `977519ad` — the AI found the 56El bug independently

Worth recording for what it confirms rather than what it asks for:

> Now that a directory off Lustre keeps its record and the walk descends
> into it, the objects under it reach this call too, and `get_projid()`
> is not tolerant of an object that is not on Lustre the way `%LF` and
> the layout fetch were just made to be ... For a symlink, fifo, socket
> or device node it takes the `LL_IOC_PROJECT` branch on the parent ...
> A regular file or directory goes through `ioctl(FS_IOC_FSGETXATTR)`,
> which only answers on a filesystem implementing `fileattr_get`. tmpfs
> does on a new enough kernel ... On a kernel where tmpfs does not, this
> fires for the plain files as well.

That is the 56El root cause, arrived at independently and in the same
detail — including the kernel dependency that explains why the lab
passed and CI did not. **Already fixed** earlier tonight; nothing to do
but note the agreement.

## 68156 — five comments, four fixed, one a false positive worth checking

| id | claim | verdict |
|---|---|---|
| `51a30d3c` | "There is no `sr_owner_fid` ... anywhere else in the tree" | **half wrong, half right** |
| `112a192f` | several paragraphs are deltas against a patch set, not the tree | real — fixed |
| `88b3e3b0` | test1's four-scan digest needs a quiescent target | real — documented |
| `3cc1db11` | `run_test_tbl()` does not set the message level | real — fixed |
| `fe739149` | the extra-area field list skips one | real — fixed |

`51a30d3c` is the one that needed checking rather than believing.
`sr_owner_fid` **does** exist — `lustreapi.h`, `liblustreapi_scan.c`,
`liblustreapi_scan_device.c`, `liblustreapi_pfind.c`. So "anywhere else
in the tree" is wrong. But it is added by **68288**, three patches
later, and 68156's message names it. The complaint is right for the
reason it did not give: a forward reference, not a nonexistent field.

That is the **fourth** instance tonight of a patch written for the tip
rather than for its own place in the series — after 68094's comments,
68417's fix, and 68158's "shared with lfind(8)". Worth naming as a
pattern: a stacked series makes it the default mistake.

`88b3e3b0` I checked rather than assumed. Running the binary against a
**mounted** MDT: all 7 tests pass, test1 included. So it describes a
latent fragility, not a present failure, and the honest fix is the
documentation half — skipping when mounted would discard a run that
demonstrably works. The header now says test1 needs quiescence, which is
a weaker requirement than unmounted, and that conf-sanity 165 never
meets it because it runs after `stopall`.

## 68094 `7f5ee1cb` — a consequence claimed one patch early

The message said the `lum_pool_name` clear is "reachable through
`lfs find -printf %Lp` once a walk descends a subtree that is not on
Lustre". At **68094** it is not: `cb_find_init()` does not call
`llapi_scan_get_lmv()` at all — `git show` on that commit finds zero
references. It joins the shared helper in **68095**, which is where the
clear first reaches `lfs find`. Reworded to say the scanner's path, and
to name the patch where the rest becomes true.

## lreview on 68157 — one finding, declined with a reason

**1 finding, 4.6M tokens, $4.39.** The split itself verifies clean:
"the predicate sequence and its early exits are unchanged, and hoisting
the `fp_get_lmv` block out from under `if (want != 0)` is safe because
`fp_get_lmv` is zeroed at the top of `cb_find_init()`".

It proposes `find_get_projid()` return `-ENOTTY` rather than `-ENOTSUP`,
so the caller's single decode covers it. **Declined: at the tip that
would be a regression.** The two codes are different answers and the
caller decodes them separately:

- `-ENOTSUP` with no path — a scan of a target, whose object genuinely
  has no project id where its inode does not reach `i_projid`:
  **undecided, and counted**;
- `-ENOTTY` — the object is not on Lustre: **does not match**, or prints
  `DEFAULT_PROJID`.

Collapsing them would report `DEFAULT_PROJID` for an object the target
could not answer for. The reviewer reasoned about 68157 in isolation,
where only the `-ENOTTY` decode exists — correctly for what it could
see, and wrongly for the series.

Its underlying observation is fair, though: two codes with one decoder
visible reads like a mistake. The helper now says why they differ and
which patch brings the second decoder, so the next reader does not have
to re-derive it.

The suggested field simplification (read `fc_rec` directly, drop
`fc_have_projid`/`fc_projid`) is mechanical and correct — all three call
sites set them from `rec->sr_valid` and `rec->sr_projid` — but it came
bundled with the return-value change, so it is left for a cleanup rather
than taken on trust at the end of a long session.

## Verification

`lfs`, `lfind`, `liblustreapi` build under `-Werror`; checkpatch 0
errors on all touched commits. Lab, ldiskfs MDSCOUNT=2 OSTCOUNT=2:

    sanity 56El, 160aa, 160ab, 160ac, 160ad   all PASS
    llapi_scan_test                           11 of 11
    llapi_scan_device_test                    7 of 7

18 changes, 18 Change-Ids.
