# 68160 `824b9aa9` — every option error printed twice

2026-09-08, eighth of the seventeen. **Real, reproduced, fixed, reproduced
fixed.** The smallest of the set and entirely uncontroversial.

`lfs_find_parse()` documents both `optind` and `opterr` as the caller's, and
asks for `opterr == 0` because it prints its own diagnostic
(`lfs_find_parse.c:1174`, `lfs_find_parse.h:111`). `lfs.c:15867` sets it;
`lfind`'s `main()` never did, so glibc's default of 1 applied and
`getopt_long_only()` printed a second one.

    $ lfind --device /tmp/lustre-mdt1 --bogus
    lfind: unrecognized option '--bogus'
    lfind: unrecognized option '--bogus'
    Usage: lfind ...

    $ lfs find /tmp --bogus            # the same mistake under lfs
    lfs: unrecognized option '--bogus'

Fixed with `opterr = 0;` beside the `argv[0]` assignment. Verified on the
lab: once each for `--bogus` and for a short `-Q`, and a good run still
answers.

**The other half of the contract needed nothing.** `optind` has to be the
index of the first argument to examine, and `lfind_parse_target()` compares
strings rather than calling `getopt()`, so it is still 1 when the parser is
reached. Said in the comment, since the two are documented together and a
reader will ask.

Setting `opterr` before `lfind_parse_target()` is safe for the same reason —
that function calls no getopt at all, so there is no diagnostic of its own to
suppress.
