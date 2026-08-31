# Round 16 — the lab record, 2026-08-31

`lab-r16` on `rhel9.7-server-mgs-mds-clone` = base + the 15 (on 99527bb5f9)
+ 68413 + 68414, MDSCOUNT=2, OSTCOUNT=1, ldiskfs.  The VM was found shut
off and restarted; the tree is `~/lustre-160ac` on branch `lab-r16`.

## sanity, ONLY_REPEAT=2

`~/12-run-r16.sh`, log `/tmp/lab-r16.log`:

    157c   PASS x2      160aa  PASS x2      160ab  PASS x2
    160ac  PASS x2      160ad  PASS x2      160y   PASS x2
    160z   PASS x2

**SKIP 0** on every one, no `error:` lines.  160z is the case with new
content this round: the disjoint-mask half, registered `-m creat` and read
back `--mask=-mark,-creat`.

## The manual checks — what no sanity case covers

`/tmp/13-manual-r16.sh`, all seven PASS:

1. `cd /mnt/lustre/rel && lfs find . --since 1h -type f` prints `./sub/f`
   — the re-spelling — and **is byte-identical to the same walk without
   `--since`**, which is the property the option promises.
2. `lfs find ./ --since 1h` composes no `//`.
3. An absolute path is unchanged: `/mnt/lustre/rel/sub/f`.
4. `lfind --local` refuses `--since-cookie`, `--changelog` and `--since`,
   each naming itself, exit 1, **and writes no cookie**.
5. `--changelog all -uid 0` and `--changelog all --mdt-hash fnv_1a_64` are
   both refused (rc=95), with the messages naming options that exist:
   "-uid, -user, -gid and -group needs the object" and "--mdt-count and
   --mdt-hash needs the object".
6. The cookie probe (`dbg2.sh`): a cookie in a **`chattr +i`** directory is
   refused up front — "cannot write the cookie ... Operation not permitted"
   — while the control shows appending to the cookie *itself* still
   succeeds, which is exactly what the old `fopen(cookie, "a")` probe
   tested and why it passed.
7. A cookie line `lustre-MDT0000 -2` is ignored rather than read as
   0xfffffffffffffffe, and the run rewrites a real index.

**A false alarm worth recording.**  The first manual run reported 1, 1b and
3 as failures with empty output.  That was the harness: it registered a
changelog user on MDT0000 only, and with MDSCOUNT=2 an object created on
MDT0001 leaves no records where no user is registered.  Registering on
every MDT makes all three pass.  Check 6 also passed for the wrong reason
at first — as `runas` it never reached the probe, failing earlier with
"'lustre' has no MDT this client can see" — which is why it was rewritten
around `chattr +i` as root.

## conf-sanity 165, 166

`/tmp/14-conf-r16.sh`, ONLY_REPEAT=2, log `/tmp/conf-r16.log`:

    165  PASS x2   (54s, 37s)
    166  PASS x2   (1s, 0s)

166 is fast but not vacuous — both iterations print "client sees 21 names
over 20 objects" and "--fid2path resolved 20 objects from 21 names,
hardlink once", which is the whole assertion set.  This is where 68288's
`$got.raw` correction lands: the "must be paths, not FIDs" check now runs
against the unfiltered output, where a FID could actually appear.

## Build

All **15 commits build individually** (`liblustreapi.la`, `lfs`, `lfind`)
on the workstation; checkpatch is clean on the round's delta apart from the
standing noise classes (MAINTAINERS for new files, the `fallthrough`
comments in code moved verbatim out of `lfs.c`, the man page's BASH
COMPLETION section, and `time_t` "misspelled").

`libscan_zfs.c` again has **no compile anywhere local** — no ZFS on the lab
VM, no headers on the workstation.  This round's change there is the projid
valid-bit restructure and two comments; Gerrit's ZFS builders are the check.
