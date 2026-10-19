# a-1019 #12: `lfs find ! --foreign=TYPE` (69795 PS1, AI e9a98930_fce7716e)

Decide-only. 69795 (08940f0ac9) not changed. Lab 2026-10-19 14:45, clone VM
192.168.122.10, loaded modules `2.17.58_65_g8618869`, FSNAME=lfst MDSCOUNT=2
OSTCOUNT=2, REFORMAT, enable_foreign_dir=1, foreign_symlink_enable=0.
Script `tests/lab-1019b/10-foreign-neg.sh`, raw output
`tests/lab-1019b/10-foreign-neg.result.txt`.

Arms (the 10-18 builds, reused; userspace only):

| arm | commit | liblustreapi_pfind.c md5 | loads |
|---|---|---|---|
| m  | master-1014 ee61b3f6dd (the base 69795 sits on) | 31e05384c3 | /tmp/arm1018m/lib |
| mf | 6ea0abfcd9 | 774721fd33 = `git show 08940f0ac9:...` | /tmp/arm1018mf/lib |

6ea0abfcd9 and 08940f0ac9 differ only in one sanity.sh skip message (the
LVM->LMV typo), so mf is 69795's code.

Fixture under `/mnt/lfst/fn` (MDT0000): `file`, `dir`, `sdir` (`lfs mkdir -c
2`, stripes on MDT0000+MDT0001), `ffile_sym` / `ffile_none` (`lfs setstripe
--foreign=symlink|none`), `fdir_sym` / `fdir_none` (`lfs mkdir
--foreign=symlink|none`). `.` is the plain top directory. One fixture, arms
alternated m mf m mf; both rounds identical.

## Results

| query | stock master (m) | 69795 (mf) | man page says |
|---|---|---|---|
| `--foreign` | ffile_none ffile_sym **sdir** | fdir_none fdir_sym ffile_none ffile_sym | the four foreign objects |
| `--foreign=symlink` | ffile_sym | fdir_sym ffile_sym | fdir_sym ffile_sym |
| `--foreign=none` | ffile_none **sdir** | fdir_none ffile_none | fdir_none ffile_none |
| `! --foreign` | . dir **fdir_none fdir_sym** file | . dir file sdir | . dir file sdir |
| `! --foreign=symlink` | . dir ffile_none **sdir** | . dir fdir_none ffile_none | . dir file sdir fdir_none ffile_none |
| `! --foreign=none` | . dir ffile_sym | . dir fdir_sym ffile_sym | . dir file sdir fdir_sym ffile_sym |

"Man page says": the EXAMPLES entry "Recursively list all but foreign
files/dirs of symlink type: `lfs find ! --foreign=symlink`", i.e. `!` negates
the whole predicate "foreign of TYPE". Bold = stock's LU-20988 inversion.

Per object, `! --foreign=symlink`:

| object | m | mf | man |
|---|---|---|---|
| . / dir (plain dir, no LMV) | yes | yes | yes |
| file (plain file) | **no** | **no** | yes |
| sdir (striped dir) | yes (inverted: read as foreign of another type) | **no** | yes |
| ffile_none | yes | yes | yes |
| fdir_none | no (inverted) | yes | yes |
| ffile_sym / fdir_sym | no | no | no |

## Conclusion

- **Plain files: upstream, unchanged by 69795.** Both arms drop `file` from
  every typed negation. That is find_check_foreign()'s `if (!foreign) { if
  (type == UNKNOWN) return exclude ? 1 : -1; return -1; }`, written that way
  in LU-11376 (6a20bdcc60, 2019) with the comment "if type specified, ...
  exclude !foreign + foreign&type". Its own comment says a typed negation
  lists only foreign objects of other types.
- **Plain directories: upstream, unchanged.** Both arms print `.` and `dir`,
  because a directory with no LMV takes the `! --foreign` shortcut
  (find_foreign_accepts(), upstream's `goto print`) before the type is
  looked at. So upstream already disagrees with its own comment here.
- **Striped directories: changed by 69795, as a consequence of the fix.**
  Stock printed `sdir` only because the inversion took its LMV for a foreign
  one of another type (the same reason stock lists it under `--foreign` and
  `--foreign=none`). With the negation restored, a striped directory is not
  foreign and follows the file rule, so it drops out. 69795 makes striped
  directories agree with plain files, not with plain directories.
- **Foreign objects: 69795 is right in every row.** `fdir_none` is now
  printed by `! --foreign=symlink`, `fdir_sym` and `ffile_sym` never are.

What the man example implies is correct: `! --foreign=TYPE` lists everything
except foreign objects of TYPE, so `file` and `sdir` belong in the answer.
That is also how `!` works on every other predicate. No arm gives that
answer; the code comment from 2019 asks for a third answer that no arm gives
either (it would drop `.` and `dir` too). The fix would be, in both branches
of find_check_foreign(), `if (!foreign) return exclude ? 1 : -1;` whatever
the type, plus a typed-negation case in 27Kf.

Recommendation: keep 69795 as it is (a one-line Fixes: patch for the
inversion; the typed rule is older and separate). The AI is right about the
semantics. Either reply only, or raise a separate LU for "`! --foreign=TYPE`
drops non-foreign files and striped directories" with this table. Draft
reply if the user agrees: "The typed-negation rule predates this patch: stock
master drops plain files the same way (lab table in hand). With the
inversion fixed, a striped directory now follows that rule. Making
`! --foreign=TYPE` match the man page is a behaviour change, so it gets its
own ticket."
