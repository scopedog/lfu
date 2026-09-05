# lreview on 68158 — three fixed, one declined

**4 findings, severity low, 6.4M tokens, $5.86.**

The useful part is the assessment, which is an independent check on the
biggest and least interesting commit in the series:

> The move itself verifies clean: `lfs.c` gains exactly 8 lines and loses
> only the moved code, every relocated helper is **byte-identical apart
> from linkage**, and the parse loop differs from the original only by
> `param.` → `param->`, `goto err` → `goto out`, and the new
> out-parameters. Behaviour of `lfs find` looks preserved on every exit
> path, including the two `--foreign` arms that used to return without
> cleanup.

That is worth having on the record: 68158 is a ~1900-line move, and it
is the change I ruled out as the cause of the `sanity-quota` failures by
file scope. An independent line-by-line verdict that the move is clean
supports the same conclusion by a different route.

## `(2)` — a patch has to read correctly at its own place in the series

The comments said the file is *"shared with lfind(8)"* and *"compiled
into both programs"*. **There is no `lfind` in the tree at this commit** —
it arrives in 68160, and `Makefile.am` here adds the file to
`lfs_SOURCES` only. Someone grepping for the second consumer finds
nothing.

The commit message already had the tense right ("arranged so lfind can
compile it"); the comments did not. Both now say the same.

This is the **third** instance of the same class tonight — 68094's
comments named fields three and five patches away, and 68417's fix had to
be written against its own version of a function later patches move. A
stacked series makes it easy to write for the tip.

## `(3)` — an unstated contract on two globals

`prev_optind` seeds `@pathstartp`, so **the caller's `optind` becomes an
argv index**. `lfs` gets away with it because `cfs_parser_execarg()`
calls through with `optind` still 1; and `lfs.c`'s `main()` sets
`opterr = 0`, so the switch default is the only place an unknown option
is reported.

Neither was written down. A second program leaving `optind` at 0 gets
`pathstart = 0` — that is `argv[0]`, the program name, returned as a
path. One leaving `opterr` at 1 gets getopt's diagnostic printed on top
of the one this prints.

Documented at the site and in the header, beside the rest of the
contract. Not made self-setting: the caller may legitimately have
consumed arguments already, and a function that resets `optind` would
take that choice away.

## `(1)` — "byte-identical" was stronger than the diff

The message claimed the loop moves byte-identical apart from
`param.` → `param->`. The reviewer counted four differences, not one.
Now stated as four and no others, and the message gains the paragraph it
was missing: `-1` does **not** mean the same thing in `@pathstartp` and
`@pathendp`, which is the subtle half of the new interface and the thing
a second caller gets wrong.

## `(4)` — declined, with the reason

The suggestion is to give the give-up paths an rc of their own so the
return value means one thing, letting `lfs_find()` swallow it and
dropping the `stopped` flag.

It is right that a return which means both "parsed" and "gave up without
an rc" is a poor interface. Declined for now because it changes the exit
codes of a shared entry point, and **adilger has open questions about
exactly this kind of API contract elsewhere in the series** — settling it
twice would be worse than settling it once. The ambiguity is documented
in the header (from thread `1343a02c`), so no caller has to discover it.

Worth revisiting when the API answers come back.

## Verification

`lfs`, `lfind` and `liblustreapi` build under `-Werror`. checkpatch:
**0 errors, 14 warnings — all pre-existing**, at lines 1111–1685, in the
moved upstream code (`fallthrough` comments, `strcpy`, `sprintf`, long
lines). My two edits are at lines 13 and 1170 and carry none of them;
the count is unchanged from before this round.

Lab smoke test on the shared parser: a plain walk, `-name`, and
`--since` all exit 0. 18 changes, 18 Change-Ids.
