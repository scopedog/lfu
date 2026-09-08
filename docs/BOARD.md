# The LFU board — one page

Every ticket and Gerrit id in play, and the ones that are *not* ours. Regenerate
the top table with `tests/gerrit-poll/gpoll.py`'s query; last refreshed
**2026-09-06**.

## The record's lifetimes are documented per field (2026-09-08)

From the user's question, not from a review comment.
`llapi_scan_namespace(3)` said only "valid only for the duration of the
callback"; it now has a **Lifetimes** subsection saying when each part stops
being the object's, because the answers differ and two are shorter than that
rule reads:

- `sr_name` points **into** `sr_path`, not beside it.
- A directory's `sr_path` is rewritten by **its own descent**, before any
  callback below it runs — it does not last until its next sibling.
- `sr_fd` for anything but a directory is closed **the moment the callback
  returns**; a kept copy names a descriptor whose number is about to be
  reused.
- `sr_lmm`/`sr_lmv` last **longer** than the rule — until the next object's
  gather — which is the more dangerous half. The record is honest within the
  callback (no layout leaves `sr_lmm` NULL), but a kept pointer describes
  whichever object was gathered most recently, and the gather clears the
  magic without clearing the body.
- The record itself is a stack local of the traversal callback, so even the
  by-value fields need the struct copied.

`llapi_scan_next(3)` is named as the exception for a consumer that needs a
record to outlive delivery, and **its own page gained the two things the
implementation shows and the prose did not**: the batch is released at the
**top** of the following `llapi_scan_next()`, before that call waits for the
scan rather than when it returns — so handing a batch to a worker thread and
calling again to overlap the next fill releases what the worker is reading,
and the `-EBUSY` that refuses a second *caller* does not refuse a *reader*
racing one. And the arena is **rewound, not freed**, so such a reader finds
the following batch's bytes rather than a fault. What that page already had
was right: everything is deep-copied, and `lfsr_parent_fd`/`lfsr_fd` are −1
because a batch cannot carry a descriptor the callback closed.

**Split across two commits:** the section into 68094, the batch sentence into
`llapi_scan_next`'s own commit, since the function does not exist at 68094.
Checked that the cross-reference never precedes the page it names, and that
no commit mixes `sr_` with `lfsr_` — this one needed **three** passes to get
right, a second hunk having applied cleanly with the new spelling while the
first conflicted.

## DONE: renumbered 165-168 to 300-303 (2026-09-08)

**adilger `5bcbf4dd`, 68156 ps16, same file and line as the AI's
`a9942381`:** *"This test number is also being used in at least one other
patch. It would be better to put this up at 300 or 400 to avoid contention
(here and in the future)."*

**So the decline posted at 15:38 is wrong and must be reversed.** It rested
on "the collision it guards against hasn't happened" — the maintainer says it
has, and said so on ps16, three days before the AI restated it. Both the
maintainer and the AI have now asked for 300/400.

**How the error happened, because it is the second time today:** the ten
adilger threads on 68156 were listed this morning and classified as "a
separate pile", then never read. The AI's `a9942381` and `4d552522` were both
*restatements* of adilger comments sitting at the same lines, and both were
answered without reading the originals. A restatement is not the comment.

**All three done.** Renumbered to **300-303** across the whole stack with one
scripted `rebase --exec` pass, `a9942381` corrected, `5bcbf4dd` answered.

**The substitution had to be anchored in the tree and could be bare in the
messages**, and knowing which is the whole job: `conf-sanity.sh` holds 14
addresses containing `192.168.`, so a bare `\b168\b` would have rewritten
them. Every message reference was enumerated first — sixteen lines, all ours
— so bare was safe there. Checked after: 14 IPs before and 14 after, and the
`EXCEPT_SLOW` duration comment (`# 8 22 40 165 (min)`) untouched.

**A second pass was needed for `test_16N` in the messages:** `_` is a word
character, so `\b166\b` never matched inside `test_166`. Caught by sweeping
every commit rather than trusting the first pass.

**Verified, not assumed:** `PASS 300 (45s)` on the lab, with
`scan_osd_ldiskfs.so` installed — so the renumber and the plugin rename are
both confirmed by a run, not by reading the diff. `Test-Parameters` now says
`ONLY=300`.

## The struct comments stop enumerating scanner capabilities (2026-09-08)

adilger `462553a5` and `611473dd`, one fix — and the first is sharper than it
reads. It is anchored on `lustreapi.h:763`, *"It offers no path and no name"*,
so he is **disputing that sentence**, not volunteering a fact: an OST object
keeps its MDT parent FID in `trusted.fid`, from which a pathname can be made.

**Our own series falsifies it two patches later.** LU-20637 (68288) reads
exactly that xattr as `lfsr_owner_fid` / `LLAPI_SCAN_OWNER` and names OST
objects from it while the OST is down. So the comment went stale **inside its
own series** — which is `611473dd`'s complaint demonstrated rather than
predicted.

Both blocks trimmed to the part that does not change: the filter sees only
what the scan already had, and 0 means a default the two scanners do not
share. The field-by-field lists go. **Nothing was lost** — both man pages
already carried the filter-time contract verbatim, and
`llapi_scan_namespace.3` already carried its own default in full, so the
header was duplicating them. `llapi_scan_device.3` gains the one sentence it
never had: what 0 means there.

**An earlier read of mine was wrong and is corrected here:** I first took
`462553a5` as "he is telling us something we already do, resolve it". It is a
correction to a claim in the comment, and the fix is a trim, not a citation.
Reading the anchor line is what changed the answer.

## Both scanners fill the stats, and the struct says it is extensible (2026-09-08)

adilger `5aae920f` and `15a0778a`, answered together — same struct, same
complaint.

**`5aae920f` — "make this extensible" was already true and written down
nowhere.** `ss_size` negotiates exactly as `lfsp_size` does: the library
writes back `min(ss_size, sizeof)` with `LLAPI_SCAN_STATS_MIN_SIZE` as the
floor, so counters appended later leave an older caller reading its own
fields. `llapi_scan_device.3` now says so.

**Deferred, with the reason:** the aggregates he wants (total size/blocks,
histograms, per-UID/GID/PRJID) and the **stats mask** to select them are one
patch and want building together. Totals change what a *namespace* scan must
read per object — a device scan has size and blocks in hand, a walk fetches
them only when asked — so the mask is what makes them affordable, and a mask
with nothing behind it is a promise.

**`15a0778a` — the namespace scanner now fills stats too.** His prediction
about staleness was already true: the comment said "the namespace scanner
does not use it" while the **changelog scanner already did**
(`liblustreapi_scan_changelog.c:1134`). The struct comment now describes the
field and names no scanner.

**Why the walk never filled it, which is the honest answer:**
`struct llapi_scan_stats` and `lfsp_stats` are introduced by **68156**, not
68094 — the field arrived with the code that needed it. So the fix lands in
68156 as well; it cannot go in 68094, where the struct does not exist.

Counted atomically, `llapi_scan_namespace()` running its callback on every
thread at once where the device scan merges per-worker counters at the end.
**Measured:** 201 objects exact at 1, 4 and 8 threads;
`seen == filtered + skipped + sum(class)` holds in every arm; a filter
rejecting every third gives 7 seen / 5 emitted / 2 filtered.
`tests/lab-r18/ns_stats.c`.

**One stale cross-reference this created and caught:** the `lfsp_search`
paragraph said it was "the same case" as `lfsp_stats` — unread by a walk.
Stats are now read by both, so that sentence was wrong the moment this
landed. Fixed in 68163.

## A no-LMA object is answered with its IGIF (2026-09-08)

adilger `e3aae0e0`, third part: *"the right place to return
inode/generation would be as an IGIF FID"*. Right, and the tree agrees —
`osd_scrub.c:632` and `:2612` build exactly that for an inode with no LMA. We
were handing out the parts and telling the consumer to assemble them, and
**nothing consumed `lfsr_gen`**: across utils, tests, headers and man pages it
was only ever produced.

So `lfsr_fid` now carries the IGIF and `LLAPI_SCAN_FID` is set;
`lfsr_gen`/`LLAPI_SCAN_GEN` are gone — which also deletes the field whose
appending parts 1 and 2 of the same comment objected to, so one change answers
all three. `lfsr_ino` stays: every object has it, and a ZFS object id is wider
than an IGIF holds. `LLAPI_SCAN_GEN`'s bit is left unused rather than
renumbering the ones above it.

**The man page had claimed the opposite** — *"One is not invented for it here
— reconstructing a FID is LFSCK's job"* — and now says an IGIF is not a
reconstruction but the FID such an inode has.

**Measured on a real no-LMA inode**, created straight on the ldiskfs side so
it has no `trusted.lma`: unfixed prints `obj:159` with 3 objects named by id
alone; fixed prints `[0x9f:0xdd8ab9ce:0x0]` and none.
`llapi_scan_device_test` 7/7.

**Three build traps in one item, all the same shape — a stale artefact
answering.** conf-sanity 300 reformatted `/tmp/lustre-mdt1`, the scan fixture,
so the unit test failed on an emptied device and looked like a regression;
the untouched image scanning fine is what separated the two. Then a
reverse-apply of one file left `lfsr_gen` used but undeclared, and
`make >/dev/null 2>&1` hid the compile error, so a **stale .so answered the
comparison and showed no difference**. Every arm since is timestamp-checked
before it is believed.

## The scan plugin is named scan_osd_ldiskfs.so (2026-09-08)

adilger `bd5ac2cf` on 68156's COMMIT_MSG: *"it would be useful to name this
consistently, like scan_osd_ldiskfs.so"*. Right, and it was our own stated
precedent that we failed to follow — the loader's comment says "plugins
beside mount_osd_ldiskfs.so, found the same way", and `mount_utils.c:511`
loads `mount_osd_FSTYPE.so`, while ours dropped the `osd_`.

Renamed in the loader, `Makefile.am` and `lustre.spec.in`; the `name` strings
stay "ldiskfs"/"zfs" so the ENOTSUP message still reads properly, with the
prefix in the path format. Split by backend: the ldiskfs half and the loader
into 68156, the ZFS half into 68163 — and 68156's loader is **single-backend**
(the `scan_backend_name[]` array arrives with 68163), so the two commits carry
different shapes of the same rename.

Verified per commit: `scan_osd_zfs.so` appears only from 68163, no
un-prefixed name survives anywhere, and the renamed plugin genuinely loads —
installed copy moved aside, no installed `scan_osd_ldiskfs.so` to fall back
on — scanning 8 directories with `--links 2` still answering 3.

## fid_is_root() moved to the UAPI header (2026-09-08)

**adilger's `3459fec3` on 68156 ps16 (5 Sep) was never answered** — the AI's
`4d552522` was restating it, and replying to the restatement is not replying
to him. He asked why `fid_is_root()` is not usable here and said the inline
can be moved to the UAPI header, or split into a `lustre_fid_server.h`.

**My reply to the AI earlier today was bad reasoning and has been overtaken.**
It gave as the objection that the move would mean deleting the server-side
definition — which *is* the move, not a blocker, and he had already said so.

Done properly: `LU_ROOT_FID` (`uapi/.../lustre_fid.h:30`) and `lu_fid_eq()`
(`:363`) are both already public, so the helper is a one-liner over things
userspace has. It now lives in the UAPI header **without `unlikely()`**, that
header being compiled in userspace, and is gone from
`lustre/include/lustre_fid.h`, which includes the UAPI one — so llite, lmv,
lod, mdd and mdt are untouched. `scan_classify()` calls it instead of
open-coding `lu_fid_eq()` against `LU_ROOT_FID`.

**Built the kernel side, not just userspace:** llite, mdt, lod, mdd and lmv
all recompiled and relinked clean, which is the check a shared-header move
needs. `tests/lift/root_fid.c` still 4/4.

Reply posted by the user on `3459fec3`, left unresolved for him to close.

**Loose end:** the AI's `4d552522` is resolved carrying the superseded claim
that the move could not be made.

## Replies posted for the sixteen (2026-09-08)

Six `gerrit review --json` calls, one per (change, patchset), targeting the
patchset each comment was written on: 68156 ps17 (3), 68157 ps17 (4), 68158
ps17 (3), 68159 ps17 (2), 68160 ps18 (1), 68163 ps16 (3). Read back
afterwards — a thread's state is its **last** comment's flag, so counting the
AI's own says nothing.

**Fifteen resolved, one left open on purpose:** 68158 `46c9be5f`, the only
pure decline, so the reviewer can push back on it. The other two declines
(68157 `0a865f6a`, 68156 `7e92da87`) each came with a change and are resolved
with the reason stated.

Every reply says **"Lands in the next patchset."** — nothing is pushed, so
`Done.` would have been a false claim. The cover message says so outright.

**Not replied to:** 68156 `a9942381`, the renumbering skipped for the user.
Answering it would be answering for a decision not made.

AI threads still unresolved: **six** — that one plus the five older
deliberate ones (68095 `937bc492`, 68156 `ab78d3de`, 68159 `e6fb45c4`,
68417 `122b863e`, 68420 `39df2275`).

## The 17 AI comments: 16 closed, 1 skipped (2026-09-08)

**Worked through in one pass.** Six were real defects, four of them
user-visible: a foreign directory dropped by `--links`, a torn linkea reported
as a non-match, an LMV buffer leaking the previous object's bytes, a chunk
boundary double-counting, `lfind` printing every option error twice, and
`lfs> find` searching the word "find". Three were declined with reasons on the
evidence (the `-ENOTSUP` sentinel, the depth check's second copy, making the
two scanners' LMV sizes agree). The rest were comments, man pages and commit
messages that said something untrue.

**Two findings came out of the work rather than the queue:**
`EXT2_SF_WARN_GARBAGE_INODES` is never set, so `EXT2_ET_INODE_IS_GARBAGE` is
unreachable as shipped — open for the user, below. And `-printf %Lc` prints a
foreign directory's `lfm_length` as a stripe count, upstream and unfixed.

Every fix is folded into its own change with a message paragraph, checkpatch
is clean over all 21 commits, the whole stack builds, and the day's diff
builds and runs on the lab. **All unpushed.**

## The AI backlog was NOT empty: 17 untriaged (2026-09-08)

The 2026-09-06 evening round left 14 unlooked-at, and **68163 carries three
more that predate it** (ps16) and were missed by every sweep since. Current
count from the REST API: 40 unresolved threads, of which 17 are AI comments
with no reply, 5 are AI threads deliberately open with a reply on them, 17
are adilger's and 1 is arshad512's.

Untriaged: 68156 `a9942381` `4d552522` `7e92da87` `edaaad1a`, 68157
`1e2c193e` `7280c834` `0f09897a` `0a865f6a`, 68158 `46c9be5f` `25ba086d`
`8516da85`, 68159 `ccbe7b56` `0aaa4e59`, 68160 `824b9aa9`, 68163 `a93f237a`
`87ba1222` `de2957d5`.

**Done: 68159 `ccbe7b56` and `0aaa4e59`, 68156 `7e92da87` and `edaaad1a`,
68157 all four, 68160 `824b9aa9`, 68156 `4d552522`, 68158's three, 68163's
three** — see below. **Seventeen triaged, sixteen closed; one skipped for
the user:** 68156 `a9942381`.

## 68163's three, unlooked-at since ps16 (2026-09-08)

The three that predate the evening round and that every sweep missed. All
real. `87ba1222`: two `-EINVAL` entries in ERRORS, the pool case folded into
the argument-check entry so there is one per errno. `de2957d5`: `sp_search`
was on neither page — `llapi_scan_device(3)` sends readers to
`llapi_scan_namespace(3)` for the structure and that page's field walk left
it out; `sp_stats` was already the model for how to say it. `a93f237a`: four
paragraphs of the commit message justified the patch against an earlier
revision of itself, which a reader from `git log` cannot see; rewritten to
state the leading-slash rule once and its consequences.
`docs/rounds/round22/68163-three.md`.

## `lfs> find` searched the word "find" (2026-09-08)

68158's three. The middle one, `25ba086d`, is a **reachable user-visible
bug**, not the contract note it was offered as: `execute_line()`
(`parser.c:384`) sets `optind = 0` for the interactive shell, `prev_optind`
seeded from that, and `lfs> find /tmp -maxdepth 0` answered
`failed for 'find': No such file or directory` before printing `/tmp`. It
searched `argv[0]`. Verbatim upstream (`5afbab284e:lfs.c:7256`), but our
patch documents a contract untrue of an in-tree caller. Fixed with
`optind ? optind : 1` — not a guess: glibc reads 0 as "reinitialise" and
scans from `argv[1]` anyway.

`8516da85`: added `lfs_find_parse_init()` beside the `fini()` already owed,
and switched both front ends to it. `lfind`'s copy of the initialiser was
**already one field short** — three of the four named, `fp_min_depth` left
implicit.

**`46c9be5f` declined on evidence:** `lfind` calls `llapi_find_device()` and
never walks, so `--mindepth`/`--maxdepth` are refused outright and the
predicted second copy of the range check never has to be written. Moving it
would make `lfind` complain that 3 > 1 for options it does not support,
ahead of the message that says so. `docs/rounds/round22/68158-three.md`.

## The root test ignored f_ver (2026-09-08)

68156 `4d552522`, and both of its points hold. `fid_is_namespace_visible()`
reaches the root through `fid_is_root()` = `lu_fid_eq()` against
`LU_ROOT_FID`, and `lu_fid_eq()` is a **whole-struct memcmp**; our
`fid_seq_is_root(seq) && f_oid == FID_OID_ROOT` ignored `f_ver`, so a root
FID with a non-zero `f_ver` was called namespace-visible where the MDT would
not. `scan_decode_lma()` swaps and stores `f_ver` off a live device, so it is
not structurally zero.

**Declined the suggested mechanism** — moving `fid_is_root()` into the UAPI
header, which would collide, `lustre/include/lustre_fid.h:133` including it,
so the server-side definition would have to go in the same patch. **Done
instead:** `lu_fid_eq(&lma->lma_self_fid, &LU_ROOT_FID)`, both pieces already
public, exact rather than approximate.

`tests/lift/root_fid.c`: **3 pass / 1 fail → 4 / 0**, with the echo-client
root — the case the spelled-out test existed for — unchanged. Byte-identical
answer on a healthy MDT. `docs/rounds/round22/4d552522-root-fid.md`.

## lfind printed every option error twice (2026-09-08)

68160 `824b9aa9`. `lfs_find_parse()` prints its own diagnostic and documents
that the caller must set `opterr = 0`; `lfs.c:15867` does, `lfind`'s `main()`
did not, so glibc's default of 1 printed a second one. Reproduced, fixed,
reproduced fixed — once each for `--bogus` and a short `-Q`, and a good run
still answers. The contract's other half needed nothing:
`lfind_parse_target()` compares strings rather than calling `getopt()`, so
`optind` is still 1 when the parser is reached, and setting `opterr` ahead of
it suppresses no diagnostic of its own.
`docs/rounds/round22/824b9aa9-opterr.md`.

## 68157's four, all on one comment (2026-09-08)

`0a865f6a`, `7280c834`, `0f09897a` sit on the same block above
`find_get_projid()`; `1e2c193e` is its commit message.

**`0a865f6a`: the code is right, the comment was wrong.** `ENOTSUP` and
`EOPNOTSUPP` really are one number, and `get_projid()` really does pass back
`-errno` unconstrained — but the sentinel is returned *before* `get_projid()`
is reached and only when `fc_path == NULL`, which is the same condition
`find_decide()` decodes it under. An `-ENOTSUP` from the ioctl keeps a path
and is reported as the error it is. `fc_path != NULL` with `fc_fdp == NULL`
is unreachable — every site sets the two together. **Declined the code
change**; fixed the comment, which named the *value* as the discriminator and
would have led a reader to drop the guard as redundant.

The other three: the stranded one-liner folded in, the "at this patch /
arrives with LU-20611" schedule dropped (it pointed at this patch's own
ticket for a caller it does not contain), and the message now names
`struct find_ctx` and `find_get_projid()`.
`docs/rounds/round22/68157-projid-comment.md`.

**The rebase went wrong twice and the tree-hash check caught it.**
`git log --grep` matched my own `fixup!` commit and the `edit` landed there;
then resolving a later commit's conflict by taking the incoming side — right
for the `find_respell()` it carried — **re-added the one-liner I had just
deleted**, so the tip held the comment twice and still built clean. Nothing
but comparing the finished tree against the pre-fold tree would have found
it. Sweep every commit, not just the tip.

## DECLINED: renumbering conf-sanity 165-168 (2026-09-08)

68156 `a9942381`, the only one of the seventeen not closed. The AI asks for a
large round number with gaps — test_300 or test_400 — so two patches adding to
this suite in parallel do not both take the next free small number.

**The premise is exactly right.** Upstream's base stops at `test_164` and then
jumps to `200a`, so 165-168 are precisely "the next four free". 300 and 400 are
both clear (200a-e, 250, 802a are the neighbours).

**Declined on the practice, and the reply is posted and resolved.** Every
conf-sanity test added upstream in the last eighteen months took the next
free number (156, 157a, 160-162, 164) or a suffixed variant of a related one
(73c-f, 82c, 28b, 88a, 123aj) — **not one jumped to a large round number**,
so 300/400 is a preference rather than this suite's convention. A parallel
patch taking 165 conflicts *textually* in `conf-sanity.sh` when the second
rebases, so the collision is detected and costs one renumber if it happens,
rather than certainly now. And `test_167` carries the CI history the Janitor
−1 on 68288 is being chased through.

**A claim of mine that was wrong, corrected here:** 165-168 do *not* sit
beside related tests. conf-sanity 160-164 are MGS/nid/registration tests; the
`lfs find` tests are in `sanity.sh`. There is no grouping argument for
keeping the numbers, and the case rests on the practice evidence alone.

**The cost, had it gone the other way:** The cost is a sweep of 25
references in the tree, 7 in the series' commit messages and Test-Parameters
(`ONLY=165`), the LU-20637 Jira thread on test_167, this board, the round
records, and ten memory files — plus the shorthand "conf-sanity 165/166/168"
that has been the working vocabulary for weeks. Renaming that is your call,
not a style fix to apply quietly.

Resolved rather than left open, unlike 68158 `46c9be5f`: this is a style
preference contradicted by the history and had been raised twice with no
answer, where `46c9be5f` is a design point that new information could
reasonably change.

## OPEN FOR THE USER: the garbage-inode flag is never set (2026-09-08)

Found while building a fixture for 68156 `edaaad1a`. `scan_ldiskfs_chunk()`
catches `EXT2_ET_INODE_IS_GARBAGE` and its comment says a body "libext2fs
calls garbage" is skipped — but `check_inode_block_sanity()` returns
immediately unless `EXT2_SF_WARN_GARBAGE_INODES` is set, and
`libscan_ldiskfs.c:271` sets only `EXT2_SF_SKIP_MISSING_ITABLE`. **Proved with
a standalone probe: flag off, libext2fs refuses nothing; flag on, it refuses
exactly the four corrupted inodes.** So that arm is unreachable today and a
garbage inode is parsed as an object.

**Not decided, deliberately.** Setting the flag makes the code do what it
says, but `check_inode_block_sanity()` verifies a checksum and an extent
header for *every inode read*, on the hot path of a scanner measured in
millions of objects a second. A throughput question, wanting its own
measurement.

## An unreadable inode at a chunk boundary counted twice (2026-09-08)

68156 `edaaad1a`. The skip arm `continue`d without asking `ino > end_ino`, so
an unreadable inode just past the bound was consumed by this chunk and read
again by the next; `ss_seen` and `ss_skipped` both took it twice. Checked
against libext2fs's own source first: `*ino` is assigned after all three of
those errors and before the return, unlike the earlier ones. A reserved inode
that could not be read was also counted as an object; now it is not.

**Measured on a real device** — a copy of the lab MDT with three of the four
inodes in the block at chunk 0's boundary (inode 75001, `end_ino` 75000)
overwritten: **unfixed 8 of 270 skipped, fixed 4 of 266.** Exactly double.
`docs/rounds/round22/edaaad1a-chunk-boundary.md`.

**A lab trap that invalidated three earlier readings:** the ldiskfs backend is
a **dlopened plugin**, not part of `liblustreapi.so`, and
`scan_backend_load()` tries `PLUGIN_DIR/scan_ldiskfs.so` *before*
`$LUSTRE/utils/`. So `make lfind` + `LD_LIBRARY_PATH` — enough for anything in
`liblustreapi` — silently ran the **installed** backend. To test a backend
change: `make libscan_ldiskfs.la`, move `/usr/lib64/lustre/scan_ldiskfs.so`
aside, set `LUSTRE=<tree>/lustre`, put it back after.

## The LMV buffer kept the last object's bytes (2026-09-08)

68156 `7e92da87`, both halves verified. `scan_lmv_to_user()` cleared only the
48-byte header of a worker's one reused 4096-byte buffer, so a directory's
shard area held whatever the last object left — **96 of 96 bytes, measured,
a preceding foreign directory's opaque value**. A consumer sizing
`lum_objects[]` by `lum_stripe_count` (as `lmv_dump_user_lmm()` does) reads
it; `rec->lfsr_lmv` points straight at that buffer. Fixed by clearing as far
as such a read can reach, bounded by the room. `sw_lmv` is now a union of the
two structures it holds, not a bare `char[]` the call site casts both ways.

**Declined:** reporting `lmv_user_md_size(count, SPECIFIC)` to make the two
scanners' sizes agree. A walk answers 144 with real shard FIDs, a device scan
48 with none — it cannot fill `lum_mds` without an FLD lookup. Agreeing on
144 would hand back zeroed FIDs as answers. Documented instead, in the record
comment and `llapi_scan_device.3`: `lum_objects[]` is measured by
`sr_lmvsize`, never by the count. `tests/lift/lmv_stale.c`, **3 pass / 1 fail
→ 4 / 0**. `docs/rounds/round22/7e92da87-lmv-size.md`.

**Two traps worth not repeating.** A non-raw Python string turned `\fI` into
a real form feed and the man page rendered `lmv_user_md_size(IcountR, ...)` —
caught by rendering the page, not by reading the diff; the tree is swept and
clean. And the fixup landing on 68156 **without** a conflict was the warning:
the `lfsr_` rename is a later commit, so the new comment named a field that
does not exist at that commit. Text now reads `sr_` there and `lfsr_` at the
tip, checked both ways.

## A torn linkea made the object a non-match (2026-09-08)

68159 `0aaa4e59`. `find_device_prefilter()`'s name loop broke out when an
entry could not be read and fell through to `return 1` — a rejection — where
the `nr == 0` case six lines above calls the same condition undecided. So an
object whose linkea claimed three names and spelled one was reported as a
non-match on a list nobody finished reading.

Reachable because `scan_linkea_entry()` caps `leh_reccount` by the *smallest*
entry that could fit, and entries are variable-length. Needs a genuinely torn
`trusted.link` — both backends deliver the whole xattr — which is the
condition `find_lmm_fits()` already exists for.

Fixed into the no-name branch's shape. **Checked and not a second defect:**
`nr == 1` with an unreadable entry 0 never reaches the loop, `scan_linkea()`
returning before it sets `LLAPI_SCAN_LINKEA`.

**Proved by lifting, not retyping** — `tests/lift/lift.py` cuts the three
static functions out of the real sources, so the unfixed arm is the shipped
text: **7 pass / 1 fail, then 8 / 0**. The first fixture was wrong (a short
first name caps `nr` to 1 and the loop never runs) and reported three
failures that were all fixture; the arms now assert the premise first.
`docs/rounds/round22/0aaa4e59-torn-linkea.md`.

**The rebase conflicted twice, usefully:** at 68159 the fields are still
`sr_`, and the `lfsr_` rename is a later commit, so the hunk was resolved
once in each spelling. Checked both directions afterwards.

## `--links` dropped a foreign directory on a device scan (2026-09-08)

68159 `ccbe7b56`, verified and **reproduced on a real device scan**.
`lmv_foreign_md.lfm_length` shares offset 4 with `lmv_user_md_v1
.lum_stripe_count`, so `find_decide()`'s nlink gate read a foreign LMV's
value length as a stripe count and asked for a stat. A walk pays one and
answers correctly; a scan has neither path nor descriptor, so the object went
undecided and was dropped **out of both `--links 2` and `! --links 2`** — the
same shape as round 22's `--projid 0` defect.

The gate is verbatim upstream (`5afbab284e:liblustreapi_pfind.c:2892`); what
this series adds is the caller with nothing to stat. Fixed with the
`lmv_is_foreign()` guard its three sibling arms already carry, folded into
68159 (`81c5db1519`) with the scripted-rebase method, tree hash unchanged.

Lab: `tests/lab-r18/09-arms-foreign-links.sh`, paired on one fixture —
**unfixed 3 pass / 2 fail, fixed 5 / 0**.
`docs/rounds/round22/ccbe7b56-foreign-nlink.md`.

**Noticed, not fixed:** `-printf %Lc` prints `lfm_length` as a stripe count
through the same aliasing. Upstream unchanged, a wrong number rather than a
dropped object — its own ticket, with the doubled-separator one.

## OWED: tell Artem the record layout moved (2026-09-07)

`struct llapi_scan_rec` now begins with `lstatx_t sr_stx` (offset 0), so it
casts to `struct statx *` and the Lustre fields follow past `0x100` —
adilger's `613572f2` on 68094, taken literally at the user's call.
`sr_size` moved from offset 0 to 256.

**PR 186 mirrors this struct by hand in Rust FFI.** Every field shifts, and
the failure is silent: during the lab run a consumer binary built against
the old layout read `seen 0xf8` where the value is `0xfdcf00000eff` — no
crash, no error, just wrong numbers. Two `static_assert`s (`offsetof == 0`,
`sizeof(lstatx_t) == 256`) protect anything compiled against our header; a
foreign-language binding gets nothing. Tell him before this lands, not
after.

Field order itself costs nothing: 100k objects, paired and alternating,
+0.02% full gather and −0.02% name-only (±0.31 ns/object).

## OWED in LU-20649: lfsr_event_time drops the nanoseconds (2026-09-07)

`liblustreapi_scan_changelog.c:615` does `co_time = r->cr_time >> 30`, so a
changelog record's event time keeps whole seconds and loses the low 30 bits
that hold the nanoseconds. Found while answering adilger's nanosecond
comment (`b3ce6f88`) on 68094, and **promised in the reply** — *"That is in
the changelog patch, LU-20649, and I will fix it there."*

**The thread is resolved**, so Gerrit will not remind us. It is the same
defect class he raised: a new interface that cannot carry the nanoseconds
another series is adding (66551, LU-1158). The object timestamps are fine —
`lfsr_stx` carries whole `struct statx_timestamp` — it is only the event
time that truncates.

## OWED upstream: a STATX_PROJID field (LU-12480, adilger's ask)

`e586539f` on 68094, 2026-09-04: push `STATX_PROJID` into the upstream
kernel so the scanner can drop its extra ioctl. Not a review finding and
nothing blocks on it — a piece of upstream work he suggested we take on.

Today `LLAPI_SCAN_PROJID` is one of the three fields gathered only when
named, because `get_projid()` opens the file when it has no descriptor. A
kernel that answered it would deliver it in the statx the MDT ioctl already
fills, and the per-object open disappears.

**The decision it will force:** `LLAPI_SCAN_PROJID` is a bit in this API's
own high half, while the low half aliases the kernel's `STATX_*`. A kernel
`STATX_PROJID` gives one field two names for the same number — unlike
`STATX_INO` vs `LLAPI_SCAN_INO`, which are two different numbers. Alias,
keep both, or deprecate ours; decide when the kernel side lands, and note
it touches `sr_projid` in the record too.

## 68288's Janitor −1 is NOT fixed, it is instrumented (2026-09-06)

`conf-sanity test_167` fails on **21 ZFS sessions** and passes on every
ldiskfs one. The 2026-09-03 `--search` fix **is** in PS11 and is not enough —
that "resolved" note was wrong. 165/166/168 all skip on ZFS, so 167 is the
scanner's only ZFS coverage in CI.

The blocker is that test_167 put `lfind`'s stdout and stderr in one file its
own `stack_trap` deletes, so **no CI artefact says why**. Fixed: stderr to
`$got.err`, quoted in the failure, as 166 and 168 already do. Built the lab
tree with `--enable-zfs` (2.2.11) and 167 **passes here**, so it is
environment-dependent — CI runs ZFS 2.3.2 on rocky8.10/9.6.
The test also now **asserts the export happened**: `export_zpool()` is an
`||` chain that leaves the pool imported and still answers 0 when anything of
it is in `/proc/mounts`, and a held pool is refused by the scan by design —
the leading hypothesis for the CI failure, and now its own error message.
`docs/rounds/round22/janitor-167-zfs.md`. No guess applied to the code.

## The directory pass stops opening the target twice (2026-09-06)

68288 `8d405103`, deferred on 2026-09-04 and now done. The map was a scan of
its own, so `--paths`/`--fid2path` opened the target twice — on ZFS an import
and an export each time — and on an OST the second open read one object and
threw the map away. It is now a **pre-pass on the same open**:
`scan_device_sweep()` lifted out of `scan_device_run()`, plus
`struct scan_prepass` and `scan_device_run_prepass()`, with
`scan_device_run()` kept as a wrapper so no earlier patch changes. The OST
refusal now comes from the target's label before either sweep runs, which is
the question the comment said we were not asking.

Measured: `--paths` now costs the same opens as a plain search (2 and 2, was
4). `llapi_scan_device_test` 7/7, `conf-sanity 165` PASS ×2.
`docs/rounds/round22/8d405103-prepass.md`.

## The find-device page claimed a lookup per object (2026-09-06)

68288 `91527192`, verified in all three parts and fixed: the NOTES said each
FID is resolved through the mount by `llapi_scan_rec_path(3)`, which for an
MDT target never happens — the map composes and there is no fallback, and the
mount is the prefix and the fsname check. `lfind(8)` had it right all along.
`fp_paths` was undocumented and `-ENOTDIR`/`-EXDEV` were missing from ERRORS;
both fixed. `docs/rounds/round22/91527192-find-device-page.md`.

## A striped directory's shard became a path component (2026-09-06)

68288 `af2ef8f0`, the evening round's other defect: verified, reproduced and
fixed. `lfind --paths` printed `/shardtest/[0x200000400:0x2:0x0]:0/f1` where
the filesystem has `/shardtest/f1`, and `--fid2path` reached it too, there
being no fallback from the map. Fixed with a new record bit
`LLAPI_SCAN_LMV_SHARD` and a nameless map entry the walk steps through, which
is the shape `mdt_path_current()` already has.
`docs/rounds/round22/af2ef8f0-dir-shards.md`.

**Left for its own patch:** `-type d` still prints the shard as an object of
its own. The principled fix is an `LLAPI_SCAN_CLS_*` class, which changes what
a scan delivers by default. **The comment's repro line is wrong** — `-c 1`
makes a plain directory here, `-c 2` is what makes shards.

## 68415's other four AI threads, all fixed (2026-09-06)

`9e911017` (a comment claiming "what every event answers for", with four
counterexamples in `scan_cl_absorb()`), `6cd44cc3` (`O_NOFOLLOW` is inert under
`open_by_handle_at()`; `O_PATH` is what makes a symlink openable), `60b237d1`
(the page cited a private symbol; it now uses the sibling's prose) and
`62e0c7ba` (the test ran outside `TEST_REGISTER`/`run_tests()` — converted, so
each case is forked and `-e`/`-o` select).

While in the test, **the DNE trap from the lab is now diagnosed rather than
suffered**: it says `... is on MDT0001, not the MDT0000 that -m names` instead
of failing with "no CL_RENAME in the stream". Run on the VM: six cases pass
forked, `-o`/`-e` select, the guard fires.
`docs/rounds/round22/68415-remaining-threads.md`.

## A filtered record stalled `_CLEAR` (2026-09-06)

68415 `e21128ea`, the second defect of the evening AI round, verified and
fixed: `sc_filter` rejecting a record left `sl_accepted` behind, so a consumer
filtering with `LLAPI_SCAN_CL_F_CLEAR` never cleared and the registered user's
backlog grew without bound. One assignment, plus the man-page half the comment
did not ask for — `_CLEAR` no longer means "never ahead of `cb`" but "never
ahead of the consumer", which widens what clearing may destroy.
`docs/rounds/round22/e21128ea-filter-clear.md`. No lab run (the user's call);
clearing needs a changelog user, which needs 68413/68414 in the same tree.

## `--since` prints each path once: LLAPI_SCAN_CL_F_ONCE (2026-09-06)

68417 `cda04667`, the thread that was **the user's call**, settled and built:
a new library flag on 68415, used by 68417/68418/68419. Coalescing collapses
an object only within `sc_min_age`, so `--since 30d` printed a daily-written
file ~30 times. The set is 16 bytes a slot against a `scan_dirmap` this series
already ships at 288, and it saves the duplicate `llapi_scan_fid()`.

Reviewing the diff caught the first version turning a duplicate into a
**miss** — a pre-window burst marked the object delivered and suppressed the
one inside the window. The `--since` window cut and the cookie anchor both
moved into `sc_filter`, ahead of the suppression.
`docs/rounds/round22/cda04667-once-flag.md`.

**RUN on the local VM and green** (`docs/rounds/round22/lab-once-flag.md`):
100010 objects between one file's two events force the eviction the 600s
`sc_min_age` cannot be faked into, and the paired arms on one build of the
modules give **unfixed 2 lines, fixed 1**, with the run's own count of changed
objects going 100022 -> 100021 — the duplicate lookup is not paid either. The
library's test5 proves its premise first (2 arrivals without the flag,
`sc_max_cached=1`) and then one with it. `sanity` 56El, 157c, 160aa-160ad
**PASS x2, zero skips**.

## New patch: the trailing-slash trim (2026-09-06)

`LU-20605 llapi: trim a start point's trailing slashes` — `02d913438a`, on
top of the stack, **under LU-20605 rather than a new ticket**. `-name`
against a start point spelled with a slash: 1 of 3 patterns correct before,
3 of 3 after. `docs/rounds/round22/lfs-find-trailing-slash.md`.

Settled against a **stock lfs built from the series base**: the doubled
path separator is upstream and not ours (ticket held, see the memory), and
68095's `-name` change was **not a regression** — stock matches nothing at
all for such a start point.

## The AI review backlog is empty (2026-09-06)

**34 replies posted; 40 open AI threads down to 7**, and all seven are
deliberate, each with a reply saying why — 68095 `937bc492`, 68156
`ab78d3de` (adilger's last word), 68159 `e6fb45c4`, 68288 `8d405103`,
68417 `122b863e` and `cda04667` (**the user's call**), 68420 `39df2275`.

Every fix from rounds 20–22 is unpushed, so the replies say **"Lands in the
next patchset"** rather than `Done.` — a `Done.` on an unpushed fix would be
a false claim. "Already fixed in a later patchset" is used only where the
current patchset genuinely carries it (68340, 68413 ps1, 68414).

## Round 22, part 2: 68094 and 68095's first AI review (2026-09-06)

Seven threads, **the first the Gerrit AI has posted on ps17/ps18**. All seven
verified, all seven real; five fixed, two answered in the message.
`docs/rounds/round22/ai-threads-68094-68095.md`.

- **`6813c461`** — `sp_want = STATX_INO` returned `stx_ino=0` with the bit
  clear, though the public header promises the whole low half and the ioctl
  fills it. `STATX_INO|STATX_SIZE` answered the same field correctly, which
  is what makes it a defect. Measured on the lab; fixed in the MDT mask.
- **`440a87f7`** — an object with **no** project id matched neither
  `--projid 0` nor `! --projid 0`, against the arm's own comment. Reproduced
  on the lab (the symlink was in neither answer, now in exactly one).
- `0397b439` the `lmd_fid` clear moved out of the shared helper; `7611a1a0`
  `LLAPI_MSG_DEBUG` quiets nothing (comment + message corrected, behaviour
  left); `d191189e` comment moved back to its function; `36c4ca49` and
  `937bc492` answered in the commit message — the latter with a measured
  three-way comparison showing new, old and `find(1)` all differ.

**Rebase hazard, met again:** `LU-20611` *moves* the project-id block, the
conflict resolution took the incoming side, and the fix committed one patch
earlier was dropped from every commit after it. Caught by grepping the
finished tree — see [[lfu-scripted-rebase]].

Verified: `range-diff` shows three commits changed in content (two more
differ only in context); `-Werror` clean; checkpatch 0/0; `sanity` 56El,
157c, 160aa–160ad **PASS ×2, zero skips**; rounds 19/21 arms still 8/0 and
17/0.

## The lab round 21 owed: RUN and green (2026-09-06)

68419/68420's seven fixes, paired A/B against the pushed PS9 build:
**11/6 unfixed → 17/0 fixed**, round 19's arms 8/0 on both, `sanity`
160aa–160ad PASS ×2 with zero skips. The gate on pushing rounds 20/21 is
therefore **cleared**. `docs/rounds/round22/lab-68419-68420.md`.

Two corrections the lab forced, which the Gerrit replies must carry rather
than a bare `Done.`: **`797f62e9`'s repro is wrong** (the shared parser
refuses first, so only a direct `llapi_find_since()` caller reaches the
message the fix changed), and **`d1c134a5`'s branch** needs a deep 4092–4095
path, not one long component.

## Round 22, unpushed (2026-09-06)

The five new AI threads on **68616** and **68617** — the reviews that landed
on the current patchsets after round 21's push. All five verified, all five
fixed; `docs/rounds/round22/ai-threads-68616-68617.md`.

- 68616 `e2548ac1` — a `.SS` closed the run for ordering but not for the
  trailing-comma test, so a run ending `.BR aaa (3),` passed silently
- 68616 `eef5b8a3` — `.P` and `.LP` are exact synonyms of `.PP` in man(7),
  and a `.P` was reported as a malformed reference
- 68616 `dd3a74a3` — a capturing group left `$1` holding `l`/`ustre`
- 68617 `94839f00`, `dc2321c4` — two commit-message counts measured off the
  wrong page state (`5 checks` is 4; the `release`→`commit` baseline is
  `1/0/2`, not `1/2/4`)

389 pages swept before and after: not one count moved. checkpatch clean.

**The unpushed pile is now three rounds deep**: round 20 on 68340/68413/
68414, round 21's seven on 68419/68420 (which still owe a lab run), and
these five.

## Ours: twenty-one changes in review (round 21 pushed 2026-09-04)

Stack order (bottom first). `PS` is the current patch set.

| Ticket | Gerrit | PS | Subject | Votes |
|---|---|---|---|---|
| LU-4315 | [68616](https://review.whamcloud.com/c/fs/lustre-release/+/68616) | 3 | contrib: let SEE ALSO carry subsections | jenkins+1, maloo+1 |
| LU-19982 | [68617](https://review.whamcloud.com/c/fs/lustre-release/+/68617) | 2 | doc: fix lustreapi.7 SEE ALSO order and AVAILABILITY | jenkins+1, maloo+1 |
| LU-20624 | [68231](https://review.whamcloud.com/c/fs/lustre-release/+/68231) | 6 | utils: fix stale fd in cb_get_dirstripe | jenkins+1, **adilger+1** |
| LU-20603 | [68094](https://review.whamcloud.com/c/fs/lustre-release/+/68094) | 17 | llapi: namespace scanner API | jenkins+1 |
| LU-20605 | [68095](https://review.whamcloud.com/c/fs/lustre-release/+/68095) | 18 | llapi: build find on the scan record | jenkins+1 |
| LU-20606 | [68156](https://review.whamcloud.com/c/fs/lustre-release/+/68156) | 17 | llapi: scan an ldiskfs target directly | jenkins+1 |
| LU-20611 | [68157](https://review.whamcloud.com/c/fs/lustre-release/+/68157) | 17 | llapi: split cb_find_init's decider out | jenkins+1 |
| LU-20611 | [68158](https://review.whamcloud.com/c/fs/lustre-release/+/68158) | 17 | lfs: share find's predicate parsing | jenkins+1 |
| LU-20611 | [68159](https://review.whamcloud.com/c/fs/lustre-release/+/68159) | 17 | llapi: run find over a device scan | jenkins+1 |
| LU-20611 | [68160](https://review.whamcloud.com/c/fs/lustre-release/+/68160) | 18 | utils: lfind, find over a target | jenkins+1 |
| LU-20613 | [68163](https://review.whamcloud.com/c/fs/lustre-release/+/68163) | 16 | llapi: ZFS backend for llapi_scan_device | jenkins+1 |
| LU-20637 | [68288](https://review.whamcloud.com/c/fs/lustre-release/+/68288) | 11 | llapi: name a device scan's objects | jenkins+1, janitor−1 |
| LU-20643 | [68340](https://review.whamcloud.com/c/fs/lustre-release/+/68340) | 3 | utils: clear stale lmd fields on reuse | jenkins+1, maloo−1 |
| LU-20647 | [68413](https://review.whamcloud.com/c/fs/lustre-release/+/68413) | 6 | mdd: look up a changelog user of either record type | jenkins+1, maloo−1 |
| LU-20648 | [68414](https://review.whamcloud.com/c/fs/lustre-release/+/68414) | 6 | mdc: fix changelog mask composition | jenkins+1, maloo−1 |
| LU-20649 | [68415](https://review.whamcloud.com/c/fs/lustre-release/+/68415) | 9 | llapi: a changelog as an Object Stream | jenkins+1 |
| LU-20650 | [68416](https://review.whamcloud.com/c/fs/lustre-release/+/68416) | 9 | llapi: fill a scan record for one FID | jenkins+1 |
| LU-20650 | [68417](https://review.whamcloud.com/c/fs/lustre-release/+/68417) | 9 | lfs: find --since, from the changelog | **jenkins−1** |
| LU-20650 | [68418](https://review.whamcloud.com/c/fs/lustre-release/+/68418) | 9 | lfs: find --changelog, the log as source | **jenkins−1** |
| LU-20650 | [68419](https://review.whamcloud.com/c/fs/lustre-release/+/68419) | 9 | lfs: find --since-cookie, per-MDT anchor | **jenkins−1** |
| LU-20650 | [68420](https://review.whamcloud.com/c/fs/lustre-release/+/68420) | 9 | tests: sanity cases for find's changelog flags | **jenkins−1** |

### The two preparatory changes (2026-09-03)

Round 18 adds a `Namespace Scanning` subsection to
`Documentation/man7/lustreapi.7`, which makes checkpatch audit the whole page:
**46 pre-existing findings**, so 68094, 68156, 68288, 68415 and 68416 showed
~48 each where they showed 1–2.

**42 of the 46 are checkpatch disagreeing with a landed upstream change.**
`e558bbedc1 LU-19982 doc: Group lustreapi.7 functions by category` (Malkeet
Singh, 2026-05-14, reviewed by Drokin, Dilger and Kansal) grouped the SEE ALSO
references into `.SS` subsections. `contrib/scripts/checkpatch-man.pl`'s
SEE ALSO checker accepts only a flat sorted run of `.BR page (N),` lines, so
every subsection's description line and every `.PP` is reported as a malformed
reference — 28 + 14 warnings. Flattening the page to satisfy it would revert
LU-19982, so the fix is to the tool.

| Count | Finding | Real? |
|---|---|---|
| 28 | `SEE ALSO lines must be of the following form` | No — every `.SS` prose line and `.PP` |
| 14 | `'.PP' should end with ','` | No — same cause |
| 2 | sort order (`llapi_pcc_state_get`, `llapi_fid_hash`) | **Yes** |
| 1+1 | AVAILABILITY names `.B lustre (8)` | **Yes** |
| 1 | ERROR: missing `release X.X.0`/`commit` for SUBJECT | Left — the page dates itself to 0.9.1 |
| 1 | CHECK: non-standard manual section | Left — the user's standing call |

After both changes `lustreapi.7` goes from `1 errors, 42 warnings, 4 checks`
to `1 errors, 0 warnings, 2 checks`. Every man page under `Documentation` was
checked before and after: **378 pages, and `lustreapi.7` is the only one whose
count changes.**

### Round 19, before the push (2026-09-03)

`lreview` — the Gerrit AI review run locally, before pushing — found three
defects on **68419**. All three verified against the tree, none already fixed,
none noise. Fixed, with a before/after measurement on the lab for each:

| Finding | Consequence before the fix |
|---|---|
| The cookie header's root read with `%s` | A search root with a space read back truncated, so **every run after the first exited `-EINVAL`**, naming a path the caller never gave |
| `%4x` on the MDT number | `-MDT0000_UUID` and `-MDT00001` **anchored MDT0000** at an index never written for it, suppressing the whole answer at exit 0 |
| `-ESTALE` absent from `llapi_find_since.3` | The error the option is built around, missing from the only place an API caller would look |

A fourth fell out of the regression arms: the old guard
`if (*num == '-' || *num == '+')` inspects only `num[0]`, so
`lustre-MDT000-1` put the sign at index 3 and `%4x` read `000` — the exact
case that guard's comment said it stopped.

`tests/lab-r18/05-arms-cookie.sh` pins all of it and is itself validated
against a build without the fix, where it fails 5 of 8 while the one arm that
must pass either way still passes. **The discriminator is
`liblustreapi.so`, not `lfs`** — `find_cookie_read()` is in the library.

The lab's own `-name` asymmetry is **documented rather than fixed** (the
user's call, 2026-09-03): the log is coalesced to one record per object, so
the only name `-name` can match is the object's *latest* event's, and the
pathname printed is its *first* name. `llapi_scan_changelog.3` now says which
event's fields the coalesced record carries, and `lfs-find.1` says which name
`-name` tests. No behaviour change.

Three commits changed: **68415**, **68419**, **68420**. Every other commit is
byte-identical by `git range-diff`, and no checkpatch count moved.

### 68156's review (2026-09-03) — five findings, five real, five fixed

10.4M tokens, $9.81, 27m38s. Every one verified against the tree first.

| # | Finding | Fix |
|---|---|---|
| 1 | The device scanner stamped `trusted.lmv` — a directory's **actual** stripe — with `LMV_USER_MAGIC`, which the tree uses for a **default** LMV (`cb_get_dirstripe()` sets it exactly when `fp_get_default_lmv` is asked for). `llite/dir.c:2274` fills `LMV_MAGIC_V1`, so the two scanners gave one striped directory two values in the same field — against `sr_lmv`'s promise that it means one thing whichever scanner filled it | `LMV_MAGIC_V1` |
| 2 | `sb_dl_handle` assigned after `dlopen()` and never read; both error paths use the local handle, and 68163 only carries it as context | field removed |
| 3 | `LLAPI_SCAN_PARENT` never named in `llapi_scan_device.3` — and `sr_parent_fid` was written unconditionally while `sr_owner_fid` twenty lines on memsets itself when insane | memset + a `.TP` |
| 4 | Missing words in the `ss_class` sentence in `lustreapi.h` | reworded to match the man page |
| 5 | The `llapi_test_utils` `run_test_tbl()` split unexplained in the message | sentence added |

**Finding 1 is a contract broken, not a wrong answer observed** —
`lmv_dump_user_lmm()` is reached only from the `getstripe`/`getdirstripe`
walk callbacks (`liblustreapi.c:3597`, `:3688`), never from a scan record. It
is what *would* break: the magic decides its `(Default)` prefix and which
fields a bare `-v` shows. Stated that way in the commit message rather than
claiming user-visible breakage.

Verified: `-Werror` clean, every checkpatch count at baseline, `sanity`
56El/157c/160aa–ad/160y/160z **PASS ×2, zero skips**, both arms suites
**8/8 and 14/14**, and the final tree diff carries only the intended changes
— the extra commit `range-diff` flagged was context-only, checked rather
than assumed.

### conf-sanity test_168, --paths (2026-09-03)

`--paths` had **no test at all** — 166 and 167 both exercise only
`--fid2path` — which is what 68288's review flagged. `test_168` scans an MDT
in service **with no mount given**, the case a filesystem whose only MDT is
the target has to be named in, and asserts one path per object rather than one
per name (20 objects from 21 names), the hardlinked object once, no FID where
a path was asked for, and **no mount point in the answer** — root-relative
being what separates `--paths` from `--fid2path`, and a mounted prefix meaning
the wrong composer ran. Plus both refusals: on an OST, and together with
`--fid2path`.

**`PASS 168 (11s)`**, and both refusals verified to fire for their own reasons
rather than incidentally. The `--paths`+`--fid2path` arm doubles as end-to-end
cover for finding (5)'s fix: it now prints the usage block and exits 1, where
before it exited 4 in silence.

### `--fid2path` does not work on ZFS, and I got this wrong twice (2026-09-03)

**`conf-sanity test_167` fails on every ZFS configuration on PS10** —
`conf-sanity4@zfs` and all twenty `conf-sanity-special@zfs` variants — with
*"lfind --fid2path on a stopped lustre-ost1/ost1 failed"* (janitor job 69464).
It passes on ldiskfs.

**How I got it wrong.** On PS9 (job 69322) I read the results page, saw
`test_167` absent from the failure and skip listings, and concluded it had
passed on ZFS. It had not run: the highest `conf-sanity4@zfs` subtest
referenced there is 166 and the `special@zfs` sessions were skipped. Absence
meant *not run*, not *passed*. PS10 touched `conf-sanity.sh` by adding
`test_168`, the Janitor re-selected the touched subtests, and 167 reached ZFS
for the first time.

**What that bad inference was used for**, all of which now needs revisiting:

1. **AI comment `db3e58ad` was declined on it** — the reviewer asked us to
   refuse `--fid2path` on ZFS, and I replied that the premise was gone. A
   correction is posted on the thread. **The reviewer was right.**
2. **The `scan_device_run()` comment was rewritten** in round 20 to drop the
   libzpool deadlock claim, on the same evidence. The failure is a failure and
   not a hang, so the deadlock claim is still neither proved nor disproved —
   but it is no longer *disproved*, which is what I claimed.
3. **68288's commit message lost a paragraph** saying `--fid2path` cannot be
   satisfied on a ZFS target at all. That paragraph may simply have been
   right.

**Lesson for the tooling:** a `WebFetch` summary of a large results page is
weak evidence. It answers what it can see and cannot distinguish "not present
because it passed" from "not present because it never ran". Ask the Janitor's
own Gerrit comment, which names failures explicitly.

**Mechanism found, fixed, and verified (2026-09-03).** The test never passed
`--search`. An exported ZFS pool is found by reading vdev labels under a
search path that defaults to `/dev`, and the framework's ZFS vdevs are
*files in `$TMP`* (`ostvdevname 1` is `/tmp/lustre-ost1`), so
`zpool_find_config()` found nothing and `lfind` answered `cannot open
lustre-ost1/ost1: No such file or directory (2)`. The fix is one line in
test_167's existing `export_zpool` branch:
`search="--search $(dirname $(ostvdevname 1))"`, folded into LU-20637.
**PASS 167 on ZFS**; 166/167/168 all pass on ldiskfs. Full account and the
four measured-and-wrong hypotheses: `docs/rounds/round20/zfs-fid2path.md`.

That settles the three items above:

1. `db3e58ad` asked us to refuse `--fid2path` on ZFS. It works on ZFS; the
   reviewer's premise was the failing test, and the test was at fault. The
   correction already posted stands as posted — no further change.
2. The `scan_device_run()` comment claims only that a second open is *not
   free*, not that it deadlocks. A standalone program does the full double
   `kernel_init`/`spa_import`/`dmu_objset_own`/disown/`spa_export`/
   `kernel_fini` cycle twice against a real exported pool and returns. The
   comment as written is supported by measurement.
3. 68288's dropped paragraph said `--fid2path` cannot be satisfied on a ZFS
   target at all. It cannot be: it is satisfied, 20 objects named. Leaving
   it out was right, for the wrong reason.

### Settled: 68094 PS16 `lustre-initialization` is **not ours** (2026-09-03)

The user pulled the logs. `mount -t lustre` for **mds2** on
`trevis-156vm260` failed with `No such device` (19) and *"Are the lustre
modules loaded?"*, and Auster exited.

**Same session, same build, mds1 mounted and reported `Started
lustre-MDT0000`** on its own node one line earlier. Identical binaries: one
MDS node registers the `lustre` filesystem type and mounts, the other does
not. vm260's dmesg carries 34 Lustre lines — all `lctl mark` DEBUG MARKERs,
so libcfs and obdclass were live there; the last one is the mount command
itself and then nothing.

A per-node provisioning problem, not a code one. 68094 touches
`lustre/utils/`, `lustreapi.h`, a man page and a test binary — **no kernel
source at all** — and jenkins is Verified+1 on the build.

The original note, kept because the reasoning was the useful part:

### Watch, not noise: 68094 PS16 `lustre-initialization` (2026-09-03)

One enforced failure on the first sessions after round 19's push:
`review-dne-part-1`, session `4912e6ca`, *"ran 2 tests. 1 tests failed:
lustre-initialization"*. Lustre never came up.

**Not called noise yet, and not called ours.** Against it being ours: jenkins
is Verified+1 with a successful build, 68094 touches no kernel module, and the
failure came from **RHEL 10.1** while the announced enforced list has
`review-dne-part-1 on el9.7-x86_64` — a distro that was not in the plan.
Against dismissing it: it is on the change carrying the scanner API, and
`lustre-initialization` is not in the known-noise list.

**The inference to avoid:** it is the only change with an enforced failure,
which looks like the one-change cluster that means a real defect. It is not —
the CI had barely started, every change had one or two of ~30 sessions
reported and **zero** "Passed enforced" anywhere. Re-check once the sweep has
run.

**Reviews still owed:** 68418 and 68288 both died on API overload (ten
retries at `529`, zero tokens); an earlier 68418 attempt died at a `500`
after $2.77. 68156 is running. Run `lreview` **one at a time** — three
concurrently is self-inflicted contention.

### The push, 2026-09-03

Round 19 went to Gerrit with the user's word. **Two new changes — 68616
(LU-4315) and 68617 (LU-19982)** — and new patchsets for the sixteen in the
main chain. Every existing Change-Id was mapped to its change before pushing;
a lost one would have created a duplicate instead of a patchset.

Checked first, and worth checking: **68415's parent on Gerrit is 68288**, and
68340/68413/68414 hang off 65345 outside the main chain, so `r16-work`
matched the chain exactly and nothing was reparented. 65345 is MERGED and is
our base commit. Our base is an ancestor of `review/master`, which has moved
on — not rebased onto it, per [[gerrit-etiquette]].

**68413 was deliberately NOT pushed.** Its `lu-20647-r18` branch is
**functionally identical to PS6** — the code matches once comments are
stripped, the only differences being two relocated comments — and its commit
message is 44 lines against PS6's 60. Pushing would spend a patchset
(≈30 test sessions, ≈150 machine-hours) to shuffle two comments and *lose*
16 lines of explanation. PS6 is the better revision and stands.

**As of 2026-09-02 17:48 every one of the nineteen carries `maloo Verified-1`**
— all of them the LU-20598 `sanity-sec` roll-up, not a defect of ours. That
now blocks landing: the Maloo annotation has stopped being free and needs the
user's login. The vote arrives with a message that says *"Passed enforced test
review-dne-part-3"*, so read the -1 against the session list and not against
the sentence attached to it. `adilger` left the series' only human vote, `Code-Review+1` on 68413 PS2,
now stale at PS6.

## 68094 and adilger, as of 2026-09-05

**PS17 carries the statx record.** `struct llapi_scan_rec`'s eleven
stat-shaped fields are one embedded `lstatx_t sr_stx`, the low
`LLAPI_SCAN_*` bits are aliases of the kernel's `STATX_*` values, and the
API's own 21 bits sit above bit 31. That is on Gerrit — 68094 PS17 and
every change above it, up to 68420 PS9 — not only on `statx-port`.

Answered to adilger on 68094 PS16, in two inline replies:

| his comment | the answer given |
|---|---|
| consumer vs scanner thread counts | the same threads: `sp_thread_count` sizes one pool and the callback runs on the worker that produced the record — N scanners calling the consumer directly, not N producers feeding one |
| bulk records instead of a callback per object | measured: ~13 ns to copy one 512-byte record into a caller's array against ~1 ns for the callback, before the layout, linkea and name it points at; and the per-object handoff is libext2fs's shape (`ext2fs_get_next_inode_full()` returns one inode, already copied out of the block buffer), not something this API adds on top of a batch |
| "unfortunate to expose a new `struct llapi_scan_rec`" — use `struct statx` or `lov_user_mds_data_v2` | statx, and the switch was already under way. **`lov_user_mds_data_v2` is not a fixed size**, which is the reason it is not the base |

His nanosecond defect (`b3ce6f88`) is closed by the same change: the
conversion that dropped `tv_nsec` on all four timestamps no longer
exists.

**Still open from his 15**, and unanswered on Gerrit:

- `sp_size`/`sr_size` versioning vs `sp_want`/`sr_valid` negotiation —
  the biggest one, and untouched by the statx work;
- FlatBuffers / Cap'n Proto, the wire-format question held 2026-08-19 and
  decided off the meeting as not ours. He expects it in *this* API, and
  it is the premise of the comment the statx switch answered;
- the `sr_`/`sp_` prefix collision and the 4 hidden padding bytes — both
  real, both cheap, both worth doing once the shape settles.

He has given **68231 a Code-Review+1**, his first vote on the series.

### Held for the next round: two lreview findings on PS17 (2026-09-05)

`lreview` on `cd2c36e8f1` — the first review PS17 has had, the Gerrit AI
having fired on ps3–ps16 and never on ps17. **2 findings, severity low**,
$8.97. Both verified, both deliberately unfixed: 68094 is the bottom of an
18-commit stack, so two sentences of qualification cost a full rebase and
repush. Bundle them with adilger's versioning answer.

| # | Finding | State |
|---|---|---|
| 1 | The header says a scan wanting nothing outside `LLAPI_SCAN_DIRENT_MASK` does no ioctl per object, and that `sp_filter` runs before any I/O. Neither holds where `readdir` leaves `d_type` unset: `llapi_semantic_traverse()` (`liblustreapi_pfind.c:5960`) calls `get_lmd_info_fd()` in its readdir loop, ahead of `cb_init`. ext4 without `filetype`, XFS `ftype=0`, and the non-Lustre trees. | **Verified in the tree.** A doc claim to qualify, not a code bug |
| 2 | Four implicit padding bytes before `sr_lmm` (three consecutive `__u32`); an explicit `sr_padding` would make the hole visible and reusable | Real — and it is adilger's `2294e6ed` restated, already held above until the struct settles |

The record is **352 bytes at 68094 and 512 at the tip**: it grows as later
commits append fields, so a size quoted without its commit means nothing.

### The batch API, built 2026-09-05 (unpushed)

`llapi_scan_namespace_open()` / `llapi_scan_next()` / `llapi_scan_close()`,
commit `047658ab63` on `statx-port-fixed`, answering adilger's bulk-records
comment. A layer over the callback API: the scan runs on its own thread and
its callback copies each record, with everything it points at, into the batch
being filled.

Measured on the lab against a real mount: **+0.4% at four threads, +0.5% at
one** with the 1024 default, against **+17.6%** for a batch of 1. Off Lustre,
where per-object work is a cached `lstat()`, +5–8% — the upper bound.

lreview found three, all real, all fixed: a single-consumer contract that was
neither documented nor enforced (**a heap overflow reproduced under ASan on
the unfixed build, 5 runs of 5**), an arena that kept only its largest chunk
(worth +1.4% → +0.4%), and `(const void **)` casts punning typed pointers
under `-O2` with no `-fno-strict-aliasing`.

Verified: 16/16 unit tests on a real mount, the equality stress IDENTICAL in
all ten arms on 20,021 objects and again on a tree carrying 1000 layouts and
an LMV, sanity 56El/157c/160aa-ad 6 PASS 0 FAIL. Numbers in
`bench-data/2026-09-05/`.

**Open**: whether it goes as a change of its own on top of 68420 or is
squashed into 68094 — asked of adilger in the drafted reply, which is not
posted.

### CI on the 2026-09-04 push

`68417`, `68418`, `68419`, `68420` are **jenkins Verified−1** on PS9
(build 131103 FAILURE) — not yet diagnosed. Janitor timeouts on
`sanity1@ldiskfs+DNE` (68094) and `sanity2@ldiskfs+DNE`, plus
`sanity3@zfs` 398g on 68417; 398g is not ours, see the not-ours list.


## Rounds 20 and 21 — pushed 2026-09-04 (18 changes, 18 new patchsets)

Recorded below as it stood at 2026-09-04 00:00, before the push. 18 changes on `r16-work`,
18 Change-Ids, builds under `-Werror`, lab green.

### The 56El regression is fixed — it blocked the whole stack

`sanity 56El` failed on 68095 and every change above it, both backends,
from round 19's CI onward. **Root cause found by lreview on 68095**:
`-printf` sets `gather_all`, which sends every object through the
project-id fetch, and 68095 made the walk descend off Lustre — where
both arms of `get_projid()` answer `ENOTTY`:

| object | fetch | fails |
|---|---|---|
| symlink, device node | `LL_IOC_PROJECT` on the parent | **any kernel** — it is Lustre's own ioctl |
| regular file, dir | `FS_IOC_FSGETXATTR` | client **older than Linux 6.0** |

CI is rocky8.10 at 4.18; the lab is rhel9.7 at 5.14, which is why it
passed here all night. Fixed in 68095, carried through 68157 and 68159.
Proved by swapping `liblustreapi.so`: **unfixed exit 25 / 347 bytes of
stderr, fixed exit 0 / none**, and the test fails against the unfixed
library.

### adilger is reviewing the series

| change | verdict |
|---|---|
| **68094** | **15 comments** — four would restructure the API, see below |
| **68095** | **approved**: "very reasonable, and correctly extracts the code from `lfs find` instead of duplicating it" — plus 2 minor, both fixed |
| 68231, 68616, 68617 | 1 each, not yet triaged |

He says he is "just going through the series" and may not hold the same
view by the end, so more are coming.

**Four of 68094's comments are open decisions for the user**, and three
are alternative answers to one question:

1. `sp_size`/`sr_size` as a version number should be `sp_want`/`sr_valid`
   negotiation, `OBD_CONNECT_*` style — a newer caller against an older
   library is refused today even asking only for old fields;
2. an array-filling call beside the per-object callback, so a 1MiB
   inode-table read is not a million callbacks;
3. piggy-back on `struct statx` rather than a similar bespoke record;
4. FlatBuffers or Cap'n Proto — the wire-format question held 2026-08-19.

One is marked a defect and is timely: the record carries **second**
resolution while LU-1158 converts the tree to nanoseconds, and its
helpers have landed. It is answered for free by 3.

Two are mechanical, real and premature: `sr_`/`sp_` collide (four
headers, and `md_op_spec`), and seven consecutive `__u32`s put **4 hidden
padding bytes** before `sr_lmm`. Both are worth doing once the struct
settles.

### lreview, run locally before pushing

Serial, one at a time. Six done, six to go.

| change | findings | outcome | cost |
|---|---|---|---|
| 68094 | 4 | 3 real — **caught a fix of mine that fixed nothing**, reverted | $8.42 |
| 68095 | 2 | **found the 56El root cause** | — |
| 68415 | 4 | 3 fixed, 1 held (API shape) | $9.13 |
| 68416 | 4 | 4 fixed | $4.32 |
| 68417 | 3 | 3 fixed — severity medium | $11.68 |
| 68420 | 5 | 4 fixed, 1 held against adilger | $8.06 |
| 68158, 68160, 68157, 68231, 68616, 68617 | — | queued | — |

**One unresolved conflict between reviewers.** lreview on 68420 wants the
client version gates back (an old client exits from getopt and the case
*fails* rather than skips); adilger had just removed them (the script
matches the client it runs on). Kept adilger's answer. `CLIENT_VERSION`
is read off the client host, not the script, and `sanity.sh` uses it 30
times — so the mismatch lreview describes is expressible. **A question
for the user to put to him.**

### Also fixed this round

- **68415**: a symlink came back from the changelog scanner with no size
  and no valid bit, where both sibling scanners answer for one.
- **68416**: `llapi_scan_fid()` cannot check `@mnt_fd` belongs to the
  same filesystem as `@fid` — the wrong mount gathers a complete record
  for an unrelated object at rc 0. Documented, as its sibling already is.
  And ~70KB of calloc per object moved behind the demand mask.
- **68417**: one unreadable object ended the whole search; encrypted
  files lost every alternate name (`<mnt>//a/f` failed the subtree test).
- **68414**: all three threads were already fixed.
- **All 89 open AI threads** are triaged and closed.

### Still open

- adilger's four API questions, and his nanosecond defect.
- The `--since` duplicate-lines trade-off (a seen-FID set costs memory
  proportional to the answer).
- **Two patches have no test driving them**: `llapi_scan_changelog_test`
  is built but nothing runs it, and nothing exercises `llapi_scan_fid()`
  at all — where their three siblings each landed a suite case with the
  scanner. Owed a test patch of its own.

## Not ours: other people's tickets that show up in our CI

| Ticket | What it is | Where we see it |
|---|---|---|
| **LU-20598** | A **session timeout**, not an assertion — the ticket's summary is *"sanity-sec test_27e: Timeout occurred after 258 minutes, last suite running was sanity-sec"*, open. Ours read 241–243 min; `sanity-sec` is only the suite the clock ran out in | Every change, deterministically. The only thing producing `maloo −1` on the series. 26 of 37 other owners' changes hit it too. Gerrit words it *"1 tests failed: sanity-sec"*, indistinguishable from a real failure — check Maloo for the timeout line |
| **LU-20523** | MDS LBUG in `tgt_grant_sanity_check()` when the ZFS MDT quota is lowered below the outstanding client grant — `sanity` **805** and **807a**. Open, filed 2026-07-25 by Oleg Drokin, affects 2.17.0 / 2.15.8 | The `%% CRASHED %%` sessions in `review-dne-zfs-part-1`. Read off 68418's crash dump 2026-09-02 |
| **LU-17857** | `sanityn test_cleanup: Autotest time out` | `review-dne-*-part-5`, six of our changes so far |
| **LU-19027** | `sanity` 271d/271f `-1 resend occured` | Data-on-MDT read-on-open |

**`sanityn` test_51d**, seen on 68340 PS3 as a `sanity-dom` failure
(`review-dne-part-4`, session `9df28be8`, 2026-08-29). `sanity-dom` runs
`sanityn` as a sub-suite, so Gerrit's `sanity-dom,sanity-quota` misnames it —
nothing in `sanity-dom`'s own subtests failed. *"rss before: 824, after 860,
some pages remained"*, an mmap/layout-lock test asserting `Rss` is exactly
zero after revocation. **Categorically not ours**: 68340 is 18 lines in
`lustre/utils/liblustreapi_pfind.c` and 51d is `dd` + `multiop` + `smaps`,
with no path between them. LU-10584 is the identical signature but
Resolved/Fixed in 2.10.6 (2018), so there is nothing open to annotate
against.

Plus the unticketed regulars with Janitor 30-day rates in the hundreds:
`sanity-pcc` 1c/1d, `recovery-small` 155, `sanity-lfsck` 18c, `sanity-hsm` 12u,
`sanity-quota` 86, `sanity` 45 and 311. See the `lfu-autotest-known-noise`
memory for the evidence behind each.

## Ours to file, after the series converges

**osd-zfs FORTIFY_SOURCE warning, unticketed.** Searched 2026-09-02: no
matching LU exists (`osd_index_it_key` returns only LU-13769 and LU-15827;
"field-spanning write" returns only LU-17545 and LU-16509, both unrelated).

```
memcpy: detected field-spanning write (size 16) of single field "&it->ozi_key"
        at lustre/osd-zfs/osd_index.c:1932 (size 8)
  osd_index_it_key <- lfsck_namespace_double_scan_one_trace_file <- lfsck_assistant_engine
```

`ozi_key` is a `__u64`; the key is 16 bytes, `sizeof(struct lu_fid)`, because
the lfsck namespace trace files are FID-keyed. **Not memory corruption** —
`ozi_key` shares a union with `ozi_name[MAXNAMELEN]`, so the write lands in
allocated space and FORTIFY is objecting to the type, not the extent. It fires
on every ZFS + lfsck-namespace run. One-line fix: copy through the union member
rather than through `&ozi_key`.

Deliberately **not filed yet**: it is outside our series, and a second
unrelated ticket in front of the same reviewers while nineteen changes are in
review costs more than it buys.
