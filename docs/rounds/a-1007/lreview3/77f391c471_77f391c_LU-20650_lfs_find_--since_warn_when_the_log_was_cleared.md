# 77f391c471 — LU-20650 lfs: find --since, warn when the log was cleared

- **Commit:** `77f391c4711b` (77f391c471, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 2.9M tokens, $1.97, 4m14s

## Overall assessment

Mostly good, one concern inline about when the oldest record is read.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 6661)

(defect) The oldest record is read after the scan, but the scan started from whatever the log held at the start. Can a clear made during the scan make this warn about records the scan already read?

lfs find registers no changelog user, so nothing holds the log for it; a purge is bounded only by the other users. For example, with a policy engine registered on lustre-MDT0000:

    lfs find /mnt/lustre --changelog lustre-MDT0000 --since 100
    # at the start the log holds 50..10000; the scan reads 100..10000
    # meanwhile the engine runs changelog_clear up to 5000
    find_since_gap() -> find_cl_first() -> oldest = 5001 > 100

The run then prints that the records before 5001 "are not in the answer", which the index wording presents as certain, while every one of them was read. A time anchor has the same window: the oldest record's time moves past `since` and the hedged warning fires for records that were in the answer.

The longer the scan, the wider the window; under --since each candidate is resolved and stat'ed through the mount.

Would reading the oldest record just before llapi_scan_changelog(), as find_cookie_purged() is placed for a cookie, describe the log the scan actually started from? find_since_gap() is silent when the read fails, so there is no duplicate error to avoid by putting it after the scan.
