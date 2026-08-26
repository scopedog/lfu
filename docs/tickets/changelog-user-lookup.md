# LU-20647 — a plainly registered changelog user cannot be looked up

**Status:** filed as LU-20647 on 2026-08-26. The fix is one commit,
`f771afbbd8`, on branch `lu-20647-changelog-user-lookup` in
`~/projects/lustre/lustre-lu20647`, based on the series base (`5afbab284e`) so
it stands alone rather than behind the LU-20462 series. Change-Id
`I12ef76c773ce31e4548db9022f381cabfe7f5ddc`. checkpatch clean, 0 errors and 0
warnings. **Not yet pushed.**

**Jira:** [LU-20647](https://jira.whamcloud.com/browse/LU-20647) ·
**Type:** Bug · **Component:** none (the LU project defines none) ·
**Affects:** 2.17.0 and master (2.17.57) — everything since LU-19296 landed

**The Description below is Jira wiki markup, not Markdown** — see the note at
the end of this file. Paste it verbatim; do not reflow it.

---

## Summary (as filed)

```
lfs changelog --user fails -ENOENT for a user registered without a mask or name
```

## Description (paste verbatim into Jira)

{{lfs changelog --user cl5 testfs-MDT0000}} fails for a changelog user that was
registered plainly. The same command works if the user was registered with a
mask or a name.

Registration and lookup disagree about the record type.

{{mdd_changelog_user_reg()}} deliberately writes the *old* record type when the
caller gave neither a mask nor a name, for compatibility
({{lustre/mdd/mdd_device.c:1785-1791}}):

{noformat}
	/* keep old record type for users without mask/name for
	 * compatibility needs
	 */
	if (mask || (name && name[0]))
		rec->cur_hdr.lrh_type = CHANGELOG_USER_REC2;
	else
		rec->cur_hdr.lrh_type = CHANGELOG_USER_REC;
{noformat}

{{mdd_changelog_user_lookup_cb()}} accepts only the new one
({{lustre/mdd/mdd_changelog.c:46}}):

{noformat}
	if ((rec->cur_hdr.lrh_type != CHANGELOG_USER_REC2) ||
	    (req->cf_user_id != 0 && rec->cur_id != req->cf_user_id) ||
	    (req->cf_user_id == 0 && strcmp(rec->cur_name, req->cf_username)))
		RETURN(0);
{noformat}

So the record is skipped, {{mcul_found}} stays 0, and
{{mdd_changelog_user_lookup()}} turns that into {{-ENOENT}}
({{lustre/mdd/mdd_changelog.c:100-103}}).
Userspace reports {{cannot set changelog filter}}.

It is the only walker in MDD that does this. Every other one takes both types
and guards the fields that exist in only one of them:

{noformat}
	mdd_device.c:248-249   changelog_user_init_cb()           accepts both, warns otherwise
	mdd_device.c:333-334   changelog_user_detect_orphan_cb()  accepts both, warns otherwise
	mdd_device.c:222       mdd_chlg_username()                reads cur_name only for REC2
	mdd_device.c:233       mdd_chlg_usermask()                returns 0 for the old type
{noformat}

The path is the shipped command, not only the library call:

{noformat}
	lfs changelog --user cl5 testfs-MDT0000
	  -> llapi_changelog_start_user()       liblustreapi_chlg.c:204
	  -> ioctl(OBD_IOC_CHANGELOG_FILTER)    liblustreapi_chlg.c:230
	  -> mdd_changelog_user_lookup()        mdd_changelog.c:76
	  -> mdd_changelog_user_lookup_cb()     mdd_changelog.c:29   -> ENOENT
{noformat}

h3. Reproducer

{noformat}
	lctl --device testfs-MDT0000 changelog_register        # -> cl5
	lctl --device testfs-MDT0000 changelog_register -m all # -> cl6
	lfs changelog --user cl6 testfs-MDT0000                # works
	lfs changelog --user cl5 testfs-MDT0000                # ENOENT
{noformat}

Note that deregistering the last changelog user purges the log, so a script
that cleans up after itself reads an empty changelog on the next run. That is
expected behaviour, not part of this bug.

h3. The fix

Accept {{CHANGELOG_USER_REC}} as well, and guard the two REC2-only fields
rather than the whole record.

This is not a one-word change, because {{struct llog_changelog_user_rec}} is
half the size of {{struct llog_changelog_user_rec2}} and has neither
{{cur_mask}} nor {{cur_name}} ({{lustre_idl.h:3084-3104}}). Today the {{||}}
short-circuits on the type test, so {{rec->cur_name}} is never reached for an
old record; simply dropping that first clause would read past the end of the
record into whatever the llog buffer holds next. So:

* a lookup *by ID* must match an old record on {{cur_id}} alone;
* a lookup *by name* cannot match an old record at all, since it has no name, and should skip it rather than compare;
* the reply's mask comes from {{mdd_chlg_usermask()}}, which already returns 0 for the old type, and the reply's username must stay empty for it.

h3. How it was found

On a lab run of the LU-20462 changelog scanner on 2026-08-25, where a plainly
registered {{cl5}} failed and {{cl6}}, registered with {{-m}}, worked. That
scanner reaches the changelog through the same ioctl, so it hit the same wall.

Introduced by {{5b85a4eb75}} (LU-19296, "changelog: retrive changelog user info
from MDT", October 2025), which added the lookup; the registration side was
already writing both types.

---

## Why this is Jira markup and not Markdown

Checked on 2026-08-26 against the live tracker. jira.whamcloud.com runs the
Jira Server wiki renderer, which does not understand Markdown:

- Backticks render as literal backticks — verified on the stored description
  of LU-20643, LU-20637 and LU-20603.
- ```` ``` ```` fences render as literal text inside a `<p>`, not as a code
  block.
- Worst case, a bare `[...]` is parsed as a link. LU-20643's description
  contains a FID in brackets and renders it as
  `<span class="error">&#91;0x742e...&#93;</span>`.

So: `{noformat}` for blocks — it is literal inside, which is what makes a FID
safe — `{{...}}` for inline monospace, `h3.` for subheadings, `*text*` for
bold, and no bare square brackets outside a `{noformat}` block.

**LU-20643's description is live and rendering badly**, and LU-20637's and
LU-20603's carry stray backticks. Worth a pass with the same rules if the user
wants them tidy.

---

## A second defect on the same path, not filed

Found while writing the fix. It is reachable today, without it, so it is its
own ticket rather than part of this one.

A zero `cf_mask` means two different things, and the client composes them as
if it meant one. `mdd_chlg_usermask()` returns 0 for a user with no per-user
mask, and `mdc_changelog.c:222` reads a zero `crs_user_mask` as *do not
filter*. But `mdc_changelog.c:811-814` composes:

```
	if (in.cf_mask == 0)
		crs->crs_user_mask = out.cf_mask;
	else
		crs->crs_user_mask = in.cf_mask & out.cf_mask;
```

so when the user has no mask and the caller passes one, the result is
`in.cf_mask & 0`, which is 0, which means *do not filter*. The `--mask` is
silently dropped and the caller gets everything.

Registering with a name and no mask already produces this today:
`mdd_device.c:1789` writes a `rec2` when *either* a mask or a name was given,
but `cur_mask` is assigned only inside `if (mask)`. So:

```
	lctl --device testfs-MDT0000 changelog register -n --user foo
	lfs changelog --user foo --mask creat testfs-MDT0000   # unfiltered
```

The fix is a third arm — `else if (out.cf_mask == 0) crs->crs_user_mask =
in.cf_mask;` — or giving "no per-user mask" a value that is not zero. It is a
wrong answer rather than an error, which makes it the more dangerous of the
two.
