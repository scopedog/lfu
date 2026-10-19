# Replies to the 2026-10-18 AI round (drafts, NOT posted)

Keyed by change and full comment id, as in triage.md. #19 gets no reply
(user choice).

## 68156
- d636e2aa_7810f44a (#1): Done.

## 68415
- f5001c3d_79a7a1f1 (#2): Done.
- 568c239a_2aa4b6f5 (#3): The tree uses this form for remote_mds_nodsh (108 times in sanity.sh, never the negated one), so it stays.

## 68416
- 4d6e64ad_c1f1dd87 (#4): Done.
- 4df24fc4_84c74c03 (#5): Declined: a directory renamed away and back gives the same name with the object reachable again; that is the flip-flop case the retry was made for (tests/lab-1013/06). The cost is bounded at SCAN_FID_RETRIES.
- 1360e218_543e97db (#6): Done. Documented, no fallback: a name-only record when the caller asked for MDT fields would drop them with no signal.
  (10-18 pm: the -EACCES text it points at was corrected locally per lreview 68416 (1): the type statx runs on every call, and root squash is named. The reply stays as drafted.)

## 68158
- 80b7eeb7_6af36526 (#7): Only lfs links this file, and these were lfs.c's names already; left as they are.

## 68160
- 768567ff_f7b15737 (#8): Done.
- 20098768_5da9a980 (#9): Done.

## 68163
- f8d7ad60_6508299b (#10): Done.

## 68288
- 8ac62df6_b32ea242 (#11): Done.
- 9c17e029_accf7832 (#12): Done.
- cf29a8b3_d89f9234 (#13): Done. scan_device_run() went too: llapi_scan_device() was its only caller.

## 68159
- 85bb9fc5_096d9840 (#14): Done. The device scanner's LMV buffer is now XATTR_SIZE_MAX (68156), so the sentence holds; the message says so.
- 64f8e0e0_b6a46bba (#15): Real, but in landed code since LU-14489; fixed separately under LU-20988.
- d55e3e04_b65d5ec4 (#16): Done.
- 2fee127e_b9be2f21 (#17): Done. SCAN_LMV_BUF is XATTR_SIZE_MAX now, which covers every foreign LMV an MDT can store; llapi_scan_device.3 says a damaged trusted.lmv comes without LLAPI_SCAN_LMV.
- 13021777_d0514133 (#18): Done.

## 68419
- 963dc2c7_f94f2e0d (#19): (no reply, user choice)
- 6b5da815_881fe259 (#20): Done.
- 397172d9_5d095b24 (#21): Done. Every covered MDT now gets a line, 0 for an empty log. A 0 whose log now starts past 1 warns rather than refuses: a log drained before the empty run looks the same, and refusing would stop every later run.

## 69502 PS9 (AI, 10-18 14:51)
- 0d84ae74_13e630ce /COMMIT_MSG:19 — Done.
  (fork-69502 reworded locally: names "llapi: pass FID and nlink to llapi_scan_fid() filter"; paragraph rewrapped. Tree unchanged.)

## 69700 PS3
- 312cc898_63b63dd4 (liblustreapi_scan_device.c ~786): Done. A pre-filter skip now takes a rate slot too.
  (Local: rate-1017 dfa074ae7d. Lab: 2000 torn inodes on an MDT image, test7 FAILs on PS3 at 0.198s of 0.500s, passes with the fix.)
