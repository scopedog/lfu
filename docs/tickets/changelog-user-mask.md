# LU-20648 — `lfs changelog --mask` is dropped for a user who has no mask

**Status:** filed as LU-20648 on 2026-08-26. The fix is one commit,
`0ea197d87b`, on branch `lu-20648-changelog-user-mask` in
`~/projects/lustre/lustre-lu20648`, based on the series base (`5afbab284e`).
Change-Id `Ib178e4c15be40c415262bf06c08da8b061855cf9`. checkpatch clean, 0
errors and 0 warnings. **Not yet pushed.** Found while writing the LU-20647
fix; reachable today without it, which is why it is its own ticket — see
`changelog-user-lookup.md`.

**Jira:** [LU-20648](https://jira.whamcloud.com/browse/LU-20648) · **Type:** Bug · **Component:** none (the LU project
defines none) · **Affects:** 2.17.0 and master (2.17.57) — everything since
LU-19296 landed

**The Description below is Jira wiki markup, not Markdown.** Paste it verbatim;
do not reflow it. Rules are in `changelog-user-lookup.md`.

---

## Summary (as filed)

```
lfs changelog --mask is silently ignored for a user registered without a mask
```

## Description (paste verbatim into Jira)

{{lfs changelog --user NAME --mask creat}} returns every record type, not just
CREAT, when NAME was registered without a mask. No error is reported. The
request is a wrong answer rather than a failure, which is what makes it worth
filing.

A zero {{cf_mask}} means two different things, and the client composes them as
if it meant one.

*Meaning one, on the server:* "this user registered no mask of their own".
{{mdd_chlg_usermask()}} returns {{cur_mask}} for a {{CHANGELOG_USER_REC2}} and
0 for the older record ({{lustre/mdd/mdd_device.c:233}}), and the lookup puts
that in the reply ({{lustre/mdd/mdd_changelog.c:53}}).

*Meaning two, on the client:* "do not filter". A zero
{{crs_user_mask}} disables the test altogether
({{lustre/mdc/mdc_changelog.c:222-224}}):

{noformat}
	/* Check if this record type matches the user's mask */
	if (crs->crs_user_mask &&
	    !(crs->crs_user_mask & BIT(rec->cr.cr_type)))
		RETURN(0);
{noformat}

The two meanings meet in {{chlg_ioctl()}}
({{lustre/mdc/mdc_changelog.c:811-814}}), where {{in}} is the mask the caller
asked for and {{out}} is the mask the user registered:

{noformat}
	if (in.cf_mask == 0)
		crs->crs_user_mask = out.cf_mask;
	else
		crs->crs_user_mask = in.cf_mask & out.cf_mask;
{noformat}

So when the caller passes a mask and the user has none, the result is
{{in.cf_mask & 0}}, which is 0, which the record test then reads as *do not
filter*. The caller's mask is dropped and everything comes back.

h3. Which users have no mask

Registration writes a {{rec2}} when *either* a mask or a name was given
({{lustre/mdd/mdd_device.c:1789}}), but {{cur_mask}} is only assigned inside
{{if (mask)}} ({{lustre/mdd/mdd_device.c:1817-1826}}). So a registration with a
name and no mask produces a {{rec2}} whose {{cur_mask}} is 0, and that user
hits this today:

{noformat}
	lctl --device testfs-MDT0000 changelog register --user foo
	touch /mnt/testfs/a ; mkdir /mnt/testfs/d
	lfs changelog --user foo --mask creat testfs-MDT0000
	  -> the MKDIR record is listed too
{noformat}

A user registered with neither a mask nor a name gets the older record type,
whose mask is 0 by definition, so every such user is affected as well. Those
users cannot be looked up at all until LU-20647 is fixed, which is the only
reason this is not visible for them yet.

h3. The fix

Either give "no per-user mask" a value that is not zero, or stop treating the
two zeros as the same thing when composing. The smaller change is a third arm:

{noformat}
	if (in.cf_mask == 0)
		crs->crs_user_mask = out.cf_mask;
	else if (out.cf_mask == 0)
		crs->crs_user_mask = in.cf_mask;
	else
		crs->crs_user_mask = in.cf_mask & out.cf_mask;
{noformat}

A user with no registered mask is not restricted to nothing; they are
unrestricted, so intersecting with them should leave the caller's mask alone.

h3. How it was found

Reading the reply path while fixing LU-20647, which makes a plainly registered
user reachable by lookup for the first time and so would have exposed this to
every such user.

---

## Notes for us, not for the ticket

**Request and reply are the same buffer.** `mdd_iocontrol()` calls
`mdd_changelog_user_lookup(env, mdd, karg, karg)`
(`lustre/mdd/mdd_device.c:2322`), and `mdt_changelog_get_user_info()` copies
`in` into `out` *after* the MDD call returns
(`lustre/mdt/mdt_handler.c:6279-6281`). So the callback overwrites the request
in place and that is what the client receives.

One consequence worth knowing before touching the callback: it writes
`reply->cf_user_id = rec->cur_id` before testing `req->cf_user_id`, so on a
lookup by name the test sees the id that was just written rather than the 0 the
caller sent, and the username is filled. The LU-20647 fix reads every `req`
field before the first write to `reply`, so it does not depend on that; anything
further should keep the same discipline.

**The test is `test_160z`, and it stands alone.** It registers a user with a
name and no mask — reachable without the LU-20647 fix — asks for `--mask creat`
and requires MKDIR to be absent, then asks without `--mask` and requires it to
be present. The second half is what keeps the fix from turning "no mask" into
"no records". Extending `test_160y` instead would have made this patch depend
on LU-20647, and the point is that it does not.

**The two patches touch the same place in `sanity.sh`.** `test_160y` and
`test_160z` are both inserted after `run_test 160x`, so whichever lands second
needs a trivial rebase. That is a textual conflict, not a dependency — either
can land first.
