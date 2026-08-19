# The plan to 2.18

**Date:** 2026-08-19 · **Constraint:** userspace tools target Lustre 2.18, the
in-kernel OSD scanner targets 2.19 (Andreas, 2026-08-19) ·
**Build order:** [`architecture.md`](architecture.md) §12

Master is `2.17.56`, the development series that becomes 2.18.0. So 2.18 is a
**deadline**, not a sequence: anything that ships in it has to be reviewed and
landed before feature freeze. That is the argument for landing pieces one at a
time, and against holding them for a larger series.

---

## Where it stands

| | State |
|---|---|
| LU-20603 · [68094](https://review.whamcloud.com/c/fs/lustre-release/+/68094) | patchset 2, `Verified+1`, **no human review**. Local commit ahead of it |
| LU-20605 · [68095](https://review.whamcloud.com/c/fs/lustre-release/+/68095) | patchset 2, `Verified+1`, no human review |
| LU-20606 · scanner | written, one commit, **unpushed** |
| LU-20611 · `lfind` | written, four commits, **unpushed** |

Seven local commits on `lu-20603-scan-api`. Everything is verified against
synthetic images and byte-comparison; **nothing has run on a real MDT**, and the
lab was deleted on 2026-08-18.

The local LU-20603 commit is ahead of what Gerrit has by four things, each
found by building the next piece: `sr_projid` on both producers, an explicit
`LLAPI_SCAN_MDT_MASK`, a `sp_size` rule that lets the parameter struct grow, and
the man page's release (2.19.0 → 2.18.0). That is the incremental method
working, and the reason to keep 68094 unlanded a little longer.

---

## A. The contract, before 68094 lands

**The only work here with an irreversible deadline.** `struct llapi_scan_rec`
and `struct llapi_scan_param` are exported: free to change now, an ABI event
after landing. Everything else in this plan is internal or new API and stays
cheap.

1. **HSM state.** `trusted.hsm` is tier 2 in the scanner design, PCC-RO and
   tiering are 2.18 consumers that need it, and the record has no field and no
   bit. One bit, one field, one tier-2 read.
2. **Say what the record is not.** It holds five pointers and two descriptors,
   so it can never cross a kernel or wire boundary; the Object Stream is a
   separate flat encoding. A paragraph in the header, not a design — it stops
   both the review question and the 2.19 surprise.
3. **Filter intent.** `sp_filter` is a callback, which serves an in-process
   consumer. A serializable filter is needed only across the kernel and RPC
   boundaries, so it is 2.19 work; state that the field is expected and leave
   room for it.
4. **LMR replica bit.** Reserve it, or accept it as an appended field later.

**Open decision:** whether to ask Andreas first. Recommended: **both** — put the
question in the LU-20606 comment (§C, which is being posted anyway) and
implement in parallel. The field is small, and dropping one before landing costs
nothing if he wants a different shape.

## B. Verification, before pushing LU-20606 and LU-20611

Rebuild a lab: `tests/lab-scan/` stages 01→04, about 40 minutes.

1. **`sanity` 56\*** — the whole proof that moving the parser and splitting
   `cb_find_init()` changed nothing. Nothing else substitutes for it.
2. **conf-sanity test_165** — the scanner's oracle: every FID the client sees
   must come off the device, and `lfind --type f` must return every regular file
   and no directory.
3. **`sanity` 157c** — re-run against the amended 68094, which has changed since
   its last Maloo run.
4. Opportunistic while a real MDT exists: `--target` and `--local`, which have
   only ever exercised their no-targets path; and a scan of a mounted, serving
   MDT, which is the torn-read case no synthetic image reproduces.

## C. Ticket hygiene — cheap, and it unblocks the review

Nothing here is hard; all of it is visible to the people whose review everything
else waits on.

- **Components** are empty on all four tickets: `llapi` for LU-20603 and
  LU-20606, `utils` for LU-20605 and LU-20611.
- **LU-20611's description** is the older block and renders mangled; the
  replacement is in [`tickets/lfind.md`](tickets/lfind.md).
- **LU-20606's comment** has never been posted; it is in
  [`tickets/llapi-scan-device.md`](tickets/llapi-scan-device.md), and it is
  where the HSM question (§A) can ride.
- **LU-20462's own description is stale** — it still says "FlatBuffers /
  MsgPack" when Andreas ruled MsgPack out on 2026-08-18 and added Cap'n Proto.
  It is the document everyone reads.
- Tell him the parent-FID-and-name item from his last round
  (`docs/local/…` A3/B1) is **done** at the record level.

## D. Then push, in this order

1. **68094 + 68095**, carrying §A and the four fixes already made. This is also
   what the re-wrapped commit messages have been waiting for.
2. **LU-20606**, once §B has run.
3. **LU-20611**, once `sanity` 56\* is green.

Pushing 20606 and 20611 onto a series with no human review adds two more
changes nobody has looked at. The counter-argument is that the scanner is the
piece with the performance story, and it may be what prompts a review. Post §C's
comment first and see.

## E. The rest of 2.18, in priority order

1. **Aggregate / histogram Filter Rules** (step 4). Andreas named the bounded
   histogram as a requirement for the Trash Can tool, so this is a consumer
   blocker, not a reporting nicety.
2. **ZFS backend behind `llapi_scan_device()`** (step 3b). The cheapest test
   that the backend ABI generalises, which is the whole claim of the plugin
   split; the prototype's ZFS scanner already exists to port.
3. **Named consumers** — PCC-RO and the Trash Can utility. Read the LU-19598
   `ltrash_purge` patch first and see whether `lfind`'s output can back it.
4. **Changelog Input Scanner** (step 5), if the window allows.
5. **Object Stream encoder** in userspace. The format is Andreas's call and is
   between FlatBuffers and Cap'n Proto; the encoder is ours once it is chosen.

## F. Parked for 2.19

The OSD API scanner and its `circ_buf` ring, the bulk RPC filter modules and
`OBD_CONNECT2_LFU`. Both are already designed and partly prototyped here. The
decisions they need — the wire format, the serializable filter, the resume
protocol after `LFU_REC_GAP` — should be *settled* during 2.18 rather than
implemented, so that 2.19 opens with them answered.
