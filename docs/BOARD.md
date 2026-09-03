# The LFU board — one page

Every ticket and Gerrit id in play, and the ones that are *not* ours. Regenerate
the top table with `tests/gerrit-poll/gpoll.py`'s query; last refreshed
**2026-09-02**.

## Ours: nineteen changes in review

Stack order (bottom first). `PS` is the current patch set.

| Ticket | Gerrit | PS | Subject | Votes |
|---|---|---|---|---|
| LU-20624 | [68231](https://review.whamcloud.com/c/fs/lustre-release/+/68231) | 4 | utils: fix stale fd in cb_get_dirstripe | jenkins+1, maloo−1 |
| LU-20603 | [68094](https://review.whamcloud.com/c/fs/lustre-release/+/68094) | 15 | llapi: namespace scanner API | jenkins+1, maloo−1 |
| LU-20605 | [68095](https://review.whamcloud.com/c/fs/lustre-release/+/68095) | 16 | llapi: build find on the scan record | jenkins+1 |
| LU-20606 | [68156](https://review.whamcloud.com/c/fs/lustre-release/+/68156) | 15 | llapi: scan an ldiskfs target directly | jenkins+1 |
| LU-20611 | [68157](https://review.whamcloud.com/c/fs/lustre-release/+/68157) | 15 | llapi: split cb_find_init's decider out | jenkins+1 |
| LU-20611 | [68158](https://review.whamcloud.com/c/fs/lustre-release/+/68158) | 15 | lfs: share find's predicate parsing | jenkins+1 |
| LU-20611 | [68159](https://review.whamcloud.com/c/fs/lustre-release/+/68159) | 15 | llapi: run find over a device scan | jenkins+1 |
| LU-20611 | [68160](https://review.whamcloud.com/c/fs/lustre-release/+/68160) | 16 | utils: lfind, find over a target | jenkins+1 |
| LU-20613 | [68163](https://review.whamcloud.com/c/fs/lustre-release/+/68163) | 14 | llapi: ZFS backend for llapi_scan_device | jenkins+1 |
| LU-20637 | [68288](https://review.whamcloud.com/c/fs/lustre-release/+/68288) | 9 | llapi: name a device scan's objects | jenkins+1 |
| LU-20643 | [68340](https://review.whamcloud.com/c/fs/lustre-release/+/68340) | 3 | utils: clear stale lmd fields on reuse | jenkins+1, maloo−1 |
| LU-20647 | [68413](https://review.whamcloud.com/c/fs/lustre-release/+/68413) | 6 | mdd: look up a changelog user of either record type | jenkins+1 |
| LU-20648 | [68414](https://review.whamcloud.com/c/fs/lustre-release/+/68414) | 6 | mdc: fix changelog mask composition | jenkins+1 |
| LU-20649 | [68415](https://review.whamcloud.com/c/fs/lustre-release/+/68415) | 7 | llapi: a changelog as an Object Stream | jenkins+1 |
| LU-20650 | [68416](https://review.whamcloud.com/c/fs/lustre-release/+/68416) | 7 | llapi: fill a scan record for one FID | jenkins+1 |
| LU-20650 | [68417](https://review.whamcloud.com/c/fs/lustre-release/+/68417) | 7 | lfs: find --since, from the changelog | jenkins+1 |
| LU-20650 | [68418](https://review.whamcloud.com/c/fs/lustre-release/+/68418) | 7 | lfs: find --changelog, the log as source | jenkins+1 |
| LU-20650 | [68419](https://review.whamcloud.com/c/fs/lustre-release/+/68419) | 7 | lfs: find --since-cookie, per-MDT anchor | jenkins+1 |
| LU-20650 | [68420](https://review.whamcloud.com/c/fs/lustre-release/+/68420) | 7 | tests: sanity cases for find's changelog flags | jenkins+1 |

**As of 2026-09-02 17:48 every one of the nineteen carries `maloo Verified-1`**
— all of them the LU-20598 `sanity-sec` roll-up, not a defect of ours. That
now blocks landing: the Maloo annotation has stopped being free and needs the
user's login. The vote arrives with a message that says *"Passed enforced test
review-dne-part-3"*, so read the -1 against the session list and not against
the sentence attached to it. `adilger` left the series' only human vote, `Code-Review+1` on 68413 PS2,
now stale at PS6.

## Not ours: other people's tickets that show up in our CI

| Ticket | What it is | Where we see it |
|---|---|---|
| **LU-20598** | `sanity-sec` fails in `review-dne-selinux-ssk-part-2` | Every change, deterministically. The only thing producing `maloo −1` on the series. 26 of 37 other owners' changes hit it too |
| **LU-20523** | MDS LBUG in `tgt_grant_sanity_check()` when the ZFS MDT quota is lowered below the outstanding client grant — `sanity` **805** and **807a**. Open, filed 2026-07-25 by Oleg Drokin, affects 2.17.0 / 2.15.8 | The `%% CRASHED %%` sessions in `review-dne-zfs-part-1`. Read off 68418's crash dump 2026-09-02 |
| **LU-17857** | `sanityn test_cleanup: Autotest time out` | `review-dne-*-part-5`, six of our changes so far |
| **LU-19027** | `sanity` 271d/271f `-1 resend occured` | Data-on-MDT read-on-open |

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
