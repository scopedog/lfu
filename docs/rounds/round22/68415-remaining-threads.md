# 68415: the four remaining AI threads (2026-09-06)

All four verified against the tree, all four real, all four fixed in
`7f934ee876` (LU-20649).

## `9e911017` — a comment with four counterexamples

`SCAN_CL_ALWAYS_MASK` was introduced as *"what every event answers for"*, and
`scan_cl_absorb()` disagrees four times: `LLAPI_SCAN_PARENT` is set only when
`fid_is_sane(cr_pfid)` — and *cleared* otherwise, because a CL_CLOSE carries
none — `LLAPI_SCAN_JOBID` only for a non-empty string, `LLAPI_SCAN_EVENT_SRC`
only when a rename's source name was copied, `LLAPI_SCAN_EVENT_UID` only with
the uidgid extension.

The mask is still right, for the reason the reviewer gives: a resolve looks up
the *object* and can supply none of those four, so skipping it costs the
consumer nothing — while it *can* supply the type, which is why
`LLAPI_SCAN_TYPE` is taken out. The comment now says "what a resolve cannot
add".

## `6cd44cc3` — `O_NOFOLLOW` under `open_by_handle_at()`

Correct: there is no pathname to resolve, so the flag enforces nothing, and the
comment credited it for the symlink handling that `O_PATH` actually does —
which the comment sixty lines below already said right (*"open_by_handle_at()
answers -ELOOP for a symlink without it"*). The first comment now attributes it
to `O_PATH` and says the flag rides along as documentation. The flag is left
in place: removing it is behaviour-neutral but touches code the lab has just
exercised, for nothing.

## `60b237d1` — a private symbol on a public page

The ERRORS entry named `LLAPI_SCAN_STATS_MIN_SIZE`, which lives in
`lustre/utils/lustreapi_internal.h` and cannot be seen or used by a reader of
the page. `llapi_scan_device.3` states the same condition in prose; this page
now matches it word for word.

## `62e0c7ba` — the test ran outside the harness

The suite called its cases straight from `main()` while `llapi_scan_device_test`
and `llapi_scan_test` register with `TEST_REGISTER` and run through
`run_tests()`. Converted: six `T*_DESC` descriptions, a `test_tbl`, `-e`/`-o`
selection, and `run_tests(mntpath, test_tbl)`. Each case is forked now, which
matters most for **test4**, whose whole subject is that bad parameters do not
crash, and test4 quiets the library around its own bad calls the way
`llapi_scan_device_test`'s test6 does, since `run_tests()` leaves the level at
`LLAPI_MSG_ERROR`.

The second half of the comment — `llapi_test_utils.c` listed in `_SOURCES`
while nothing from it was used — closes itself: the harness is what that file
provides.

**And the trap from this afternoon's lab, fixed while in there.** Under DNE the
test's own directory lands on whichever MDT the balance picked, which need not
be the one `-m` names; the cases then read a log full of somebody else's
records and fail on what is missing from it. It now says so before running
anything:

    /mnt/lustre/llapi_scan_changelog_test.d is on MDT0001,
    not the MDT0000 that -m names

## Verified on the VM, not only compiled

Built against the installed library on `rhel9.7-server-mgs-mds-clone` and run
against the live filesystem:

- all six cases **pass**, forked, exit 0
- `-o 5` runs test5 alone; `-e 0,1` skips two and runs four
- the DNE guard fires with the message above and exit 1

Amended into 68415 (`6245de0282` -> `7f934ee876`); tip identical to the tested
tree, 20 commits, 20 Change-Ids, builds in isolation, checkpatch back to its
prior counts (0 errors, 1 warning) after shortening the guard's message, which
was the one line over 80 columns.
