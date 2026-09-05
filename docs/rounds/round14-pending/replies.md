# Round 14 — the replies to post after the push

Short, per house style: "Done." where addressed, a reason only where the
answer differs from what was asked.

## 68419 (LU-20650 lfs: find --since-cookie, per-MDT anchor)

- `liblustreapi_pfind.c:3617` (foreign filesystem)
  > Done.  The header is read back now, and a cookie naming another
  > filesystem is refused rather than started over.  160ac covers it.

- `liblustreapi_pfind.c:3621` (the signed index)
  > Done, and confirmed with a probe: "-MDT-1" parses to 0xffffffff, which
  > the (int) test let through.  The sign is refused at the parse and the
  > bound is compared against the value that does the indexing.  160ac feeds
  > that line, and the arm with the old test back fails on it.

- `liblustreapi_pfind.c:3666` (fflush/ferror)
  > Done.  ferror() answers -EIO rather than errno, and fclose()'s return is
  > checked.

- `liblustreapi_pfind.c:4278` (probe inside the loop)
  > Done.  Every anchor is checked in a pre-pass before the scanning loop, so
  > the run either starts clean or refuses before printing anything.  It also
  > skips the probe for an MDT with no anchor, which was your PS1 note.

## 68414 (LU-20648 mdc: fix changelog mask composition)

- `/COMMIT_MSG:38`
  > Done.  You are right that the server does no per-user delivery filtering.
  > cfs_str2mask() seeding an absolute mask from CHANGELOG_MINMASK is the
  > reason, so two string masks always meet at BIT(CL_MARK) and the old code
  > filtered to MARK alone.  The paragraph says that now.

- `mdc_changelog.c:824`
  > Done.

- `sanity.sh:22579`
  > Done.  The comment says what the widening is actually for -- CREAT and
  > MKDIR in the recording mask -- and the commit message with it.

## 68413 (LU-20647 mdd: look up a changelog user of either record type)

- `/COMMIT_MSG:9`
  > Done.

- `mdd_changelog.c:64`
  > Done.  The name is filled from the record's own type rather than from the
  > lookup kind, so the condition no longer depends on req and reply being the
  > same buffer.

- `sanity.sh:22555`
  > Done.  160y registers a third user with a name and looks it up by that
  > name, so the walk past the plain record is exercised.
