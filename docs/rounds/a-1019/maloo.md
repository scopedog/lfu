# Maloo triage, 2026-10-19 (enforced failures, current PS)

All 11 failed sessions are on the current PS (checked with `gc info`). No other
failed enforced session on 68416-69729.

| Change/PS | Session (group) | Suite / subtest | Signature | Ticket | Action |
|---|---|---|---|---|---|
| 68417 PS24 | e94386a0 (dne-zfs-part-4, el9.8) | sanity-quota 2 | inode hardlimit 2048: touch after 1024+EDQUOT succeeds, "user create success, but expect EDQUOT" | LU-15879 | linked + retested |
| 68419 PS24 | 35659468 (dne-zfs-part-4, el10.1) | sanity-quota 90a | `lfs quota` with/without mount differ by 1 KB of root usage (35302 vs 35301) | LU-20774 | linked + retested |
| 69502 PS10 | dd06148c (dne-zfs-part-4, el10.1) | sanity-quota 90a | same, 35300 vs 35298 | LU-20774 | linked + retested |
| 69443 PS12 | 15cafdd0 (dne-zfs-part-4, el10.1) | sanity-quota 3c | "Write before timer goes off" gets EDQUOT, "write failure, but expect success" | LU-18532 | linked + retested |
| 69729 PS4 | 7c9465bc (review-ldiskfs, el8.10) | sanity 205l | "seq_write wrote 0 jobs expected 500" | LU-18601 | linked + retested |
| 68418 PS24 | 72504f45 (dne-zfs-part-1) | sanity 160h | "mds1: User cl10 not registered" right after register | LU-15566 (candidate) | NONE: 160*, for the user |
| 69502 PS10 | fe0914a0 (dne-zfs-part-1) | sanity 160h | "mds1: User cl10 not registered" | LU-15566 (candidate) | NONE: 160*, for the user |
| 69503 PS10 | a735f2c5 (dne-zfs-part-1) | sanity 160h (+160i/j fail, 160k TIMEOUT 259 min) | "expected 2 GC-thread"; console: GC on MDT0000 starts (force deregister cl11) 80 ms before fail_loc=0x1316, then cascade | LU-20884 (exact) | NONE: 160*, for the user |
| 69729 PS4 | d29abb7c (dne-zfs-part-1) | sanity 160h | "mds1: user cl11 index expected 25, but is 26" | none for 160h; LU-20813 is the same race in 160g | NONE: 160*, for the user |
| 68416 PS31 | 19ede66f (dne-part-4, el10.1) | sanity-hsm 400 | after 300-302 MDT restarts: "lustre-MDT0000-osp-MDT000N: This client was evicted by lustre-MDT0000", osp_attr_get rc=-5, `lfs mkdir -i1` EIO | none (LU-20990 is sanity 43A, same EIO, not an eviction) | NONE: no ticket |
| 69700 PS4 | d252953d (dne-ipv6, el9.8) | sanity 64f | "direct io with grant allocation: grants mismatch: 43712512, expected 108552192" | no open LU (LU-20699 closed Duplicate, moved to EX-15678) | NONE: no ticket |

160h evidence that it is not ours: 4 failures in 144 lustre-reviews runs over 21 days.
3 are ours (69502, 69503, 69729). The 4th is 69614 (Zhenyu Xu, LU-20935 llite
encryption), which hit the same "User cl10 not registered". The tree tested by 69729
has no changelog code of ours; its 160a-160y are upstream. sanity-hsm 400: 1 failure
in 100 runs (ours only). sanity 64f: 1 failure in 132 runs (ours only).
