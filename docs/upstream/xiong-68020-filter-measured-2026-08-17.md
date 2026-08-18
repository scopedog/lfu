# LU-20591's Filter (68020) Against Ours, on One Box

**Date:** 2026-08-17
**Their change:** [68020](https://review.whamcloud.com/c/fs/lustre-release/+/68020)
`LU-20591 target: select iterated objects by size and time` — patch set 1
(`a7268a7a2a`), status NEW, **`Verified: -1`**, unchanged since 2026-08-14 21:02.
68019 (`7ad8529dda`) and 68018 (`dad4c95a8c`) are ancestors; base tag 2.17.57.
**Ours:** v2_17_55 + the six-patch stack.
**Raw data:** [`bench-data/2026-08-17/xiong-68020-vs-ours.txt`](../../bench-data/2026-08-17/xiong-68020-vs-ours.txt)

The internal collision analysis (`docs/local/`, not published) §7 measured their
*enumeration* on 2026-08-15. This measures their **filter**, which is what 68020
adds and what our own filter work of this morning makes directly comparable.

**Method.** One GCP c3-standard-8, one MDT image, one namespace: 302,122 objects
across four OSTs with a pool, and `shapes/big1` — **1.5 GiB striped over four
OSTs, with `trusted.som` written**. Two source trees, module sets swapped between
rounds with `make install` + `depmod` + remount, so the two rounds differ only in
which modules are loaded. Their MDT callback filters `fid_is_norm() &&
S_ISREG()`, so it counts 302,012 where we count 302,122; the ~110-object gap is
directories and internal objects, and fewer objects is less work, so their rate is
if anything flattered.

---

## 1. Ground truth first: what the MDT actually holds

Before either scanner, straight off the device:

```
the client:  size=1610612736 blocks=3145728   fid=[0x200000401:0x7:0x0]
debugfs, MDT inode 11001992:
  Inode: 11001992   Type: regular   Mode: 0644
  Links: 1   Blockcount: 0
trusted.som on that inode:
  04 00 00 00 00 00 00 00 00 00 00 60 00 00 00 00  00 c0 2f 00 …
  lsa_valid = 0x0004 (SOM_FL_LAZY), lsa_size = 0x60000000 = 1,610,612,736
```

**The MDT inode holds size 0 and blockcount 0 for a 1.5 GiB file.** The real
number is in `trusted.som`, and it matches the client exactly. This is
[`filter-levels.md`](../filter-levels.md) §4 as a hex dump.

## 2. Their `--size` on an MDT selects on that zero

`mdt_scrub_iter_rec()` does `dt_locate()` + `dt_attr_get()` — unconditionally,
because it needs `la_mode` for its `S_ISREG()` test — and then
`scrub_iter_filter_match(filter, &la)` compares `la.la_size`. On an MDT that is
the inode's size.

| MDT, the 1.5 GiB 4-stripe file | theirs (68020) | ours |
|---|---|---|
| size the walk reports for it | **0** | **1,610,612,736** |
| `--size +1G` | **0 objects** | **1** |
| `--size +100M` | 0 | 1 |
| `--size -1M` — "small files" | **302,011 — and the 1.5 GiB file is in the set** | 302,014, and it is **not** (verified: 0 matches) |

Their own commit message opens with the use case: *"a caller that is after, say,
the large files nobody has touched for a month."* On an MDT that query returns
nothing. The **other** direction is the one that would hurt: `--size -1M`
silently *includes* a 1.5 GiB file, because on the MDT it looks like zero bytes.
An omission is visible; a wrong inclusion is not.

**On an OST their filter is correct**, and their man-page example is an OST:

| OST0000 | objects |
|---|---|
| `--size +1M` | 4 |
| `--size +100M` | 1 — the 402,653,184-byte stripe |
| `--size +1G` | 0 |

402,653,184 is exactly 1.5 GiB ÷ 4 stripes. Which surfaces something bigger than
either patch: **the whole file's size is not visible on any single target** —
the MDT inode says 0, an OST object says one stripe's worth. Only
`trusted.som` on the MDT carries the file's own number, which is why our
`--size`/`--blocks` read it and why a per-target size filter that does not is
answering a different question than the operator asked.

### Why their test suite cannot catch this

`sanity-scrub.sh test_31` checks `--size` against `--print-size` from the *same
device* — no hardcoded expectations, which is good discipline and the reason it
passes. But both sides read the same `la_size`, so a filter that selects on the
wrong number agrees perfectly with a report that prints the wrong number. The
test is self-consistent and the semantics are still wrong. Catching this needs an
oracle from outside the target: the client's `stat`, or `lfs find`.

## 3. Rates: their filter earns more than ours, from a lower base

Objects **visited** per second — not emitted. A filter that emits nothing is not
a scan at infinite speed, and measuring it that way is a mistake we made in our
own reporting this morning and fixed. Medians of three, warm, one enumerator each.

| configuration | theirs | ours | ours ÷ theirs |
|---|---|---|---|
| no filter | 617,084 | 4,424,733 | **7.2×** |
| `--print-size` (their shipped default use) | 580,746 | — | — |
| rejecting tier-0 filter (`--uid 4242`) | **787,421** | **4,942,172** | 6.3× |
| rejecting (`--mtime +365d`) | 788,305 | 4,930,718 | 6.3× |
| `--size +1G` | 787,421 *(matches nothing, see §2)* | 3,184,384 *(tier 1, reads SOM)* | — |
| **filtering gain** | **+26%** | **+12%** | — |

Two things worth saying plainly, one in each direction.

**Their filter is worth more, proportionally, than ours.** +26% against our +12%,
and that is their design working: their transport copies a fixed-size item to
user space per object under a pull ioctl, so not copying it saves real work. Our
ring write is cheaper per record, so we have less to save by skipping it. The
§3.5 prediction — "filtering saves `copy_to_user` bandwidth, not scan work" — was
right about the mechanism and wrong to imply the saving was small.

**And their absolute rate is 6–7× lower**, for the reason §3.1 identified and §7
measured: `dt_locate()` + `dt_attr_get()` per object is the OI lookup and the
`iget` that block parsing exists to remove. Their filter cannot help with that,
because it runs *after* the attribute read — the expensive step is the input to
the filter, not something the filter can avoid. Ours rejects on attributes that
came free out of the mapped inode-table block, and only then reads an xattr, and
only if the surviving object needs one.

That is the whole difference in one line: **for them the attributes are the cost
and the filter saves the transport; for us the attributes are free and the filter
saves the transport too.**

## 4. What we would take from 68020

Unchanged from §3.5, and the measurements strengthen two of them:

- **Ranges instead of value-plus-comparator.** `newer than`, `older than` and
  find(1)'s "exactly N units ago" collapse into one rule; user space decides what
  a unit means. Cleaner than our `LFU_OP_GT`/`LT`/`EQ`-plus-margin, which had to
  reimplement `find_value_cmp()`'s margin semantics to stay faithful.
- **Unknown filter fields refused with `-EOPNOTSUPP`, not ignored**, because
  ignoring one silently widens the result. Our `lfu_filter_validate()` rejects
  malformed payloads but does not have this property by construction; it should.
- **`DOIF_NOSCRUB`**, already adopted as the recommendation.

And one to offer back: **a size filter on an MDT needs `trusted.som`.** The fix
is small and local — read the xattr where the attributes are already being read —
and it is the difference between their headline use case working and returning
nothing. Our `rec(DORA_XATTR)` extension is one way to get it without paying a
second `dt_locate`.

## 5. Fairness

Patch set 1, self-described on the ticket as AI-generated, `Verified: -1`, and
untouched for three days. These numbers measure an early draft against work that
has had four days and five labs. The pull transport also yields the device
between batches deliberately, so some of the rate gap is politeness rather than
inefficiency, and the `S_ISREG` scope makes their object set smaller than ours.

None of that touches §2, which is not a performance claim: the size a filter
selects on is either the file's or it is not, and on an MDT theirs is not. That
is worth raising on the ticket regardless of what happens to the rest of the
series — and it is the same trap our own `-b` flag fell into until this morning,
which is the least self-congratulatory way to raise it.

**Our own variance, for honesty:** our unfiltered rate measured 3,587,401 earlier
today and 4,424,733 here, on the same box and namespace, differing only in cache
state after a remount. Their 617,084 here against 604,487 on 2026-08-15 is much
tighter. Cross-run comparisons of our figures need that ±20% in mind; the
within-table ratios above do not.
