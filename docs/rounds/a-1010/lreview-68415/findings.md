# HEAD — LU-20649 llapi: add llapi_scan_changelog()

- **Commit:** `4f1d0dfee3d1` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 3.8M tokens, $2.97, 5m12s

## Overall assessment

Mostly good, one concern inline about how a clear's -ENOENT is told apart for a user registered without a mask or name.

## Findings

### 1. `lustre/utils/liblustreapi_scan_changelog.c` (line 1088)

(defect) Does scan_cl_user_registered() answer true for a user registered the plain way?

It asks through llapi_changelog_start_user(), which ends in mdd_changelog_user_lookup_cb(), and that skips every record whose lrh_type is not CHANGELOG_USER_REC2:

    if ((rec->cur_hdr.lrh_type != CHANGELOG_USER_REC2) ||

mdd_changelog_user_register() writes CHANGELOG_USER_REC when neither a mask nor a name is given, so for `lctl changelog_register` with no options the lookup returns -ENOENT and this reads the user as unregistered. mdd_changelog_clear_cb() matches on cur_id alone, so the clear itself works for that user, and the "already cleared" -ENOENT is then kept as a failure.

The case is not exotic: a new user's cur_endrec starts at mc_index, so with another user holding older records, a first run with sc_startrec = 0 and _CLEAR clears below it on the first batch. The run returns -ENOENT with nothing wrong, and under _FOLLOW it ends there. An MDS before 2.17.0 gives the same result, since it cannot do the lookup at all.

The page says of this -ENOENT that it "means that sc_user is not registered" and that a clear below the user's point "is not an error", and its LU-20647 note under sc_user is limited to sc_type_mask. Should the lookup failing be kept apart from "not registered", or the limit be stated for _CLEAR as well?

Two smaller things on the same path, if the patch is refreshed: the probe passes only CHANGELOG_FLAG_EXTRA_FLAGS, so llapi_changelog_start() prints its one-time "called without CHANGELOG_FLAG_JOBID" warning from inside the library; and each failed lookup logs "cannot set changelog filter" here plus a CERROR on the client, once per clear batch.
