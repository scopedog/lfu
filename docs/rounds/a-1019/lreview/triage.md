# lreview a-1019 triage

| # | change | sha | finding | verdict |
|---|---|---|---|---|
| L1 | 68415 | ab51ae86d5 | scan_changelog.c:1284: lfsc_type_mask with empty intersection vs the user's registered mask = mdc filters nothing (crs_user_mask 0), caller gets every type | REAL (verified: no library-side type check in the read loop). Take: drop records whose type is not in lfsc_type_mask; drop the man caveat |
| L2 | 68416 | e30c9f3e0d | clean | - |
| L3 | 68419 | 07b1fc5ddd | commit msg ~230 lines restates code comments | DECLINE (same call as the 68163 long-msg nit, 10-18) |
| L4 | 68419 | 07b1fc5ddd | pfind.c:6157 + llapi_find_since() Return: block not reflowed | Take (reflow only) |

Cost: 68415 $3.95, 68416 $2.86, 68419 $3.96.

## Batch 2 (68156 work, $23.3)

| # | change | sha | finding | verdict |
|---|---|---|---|---|
| B1 | 68156 | b39fe0036b | scan_device.c:768: pre-2.6 OST (no IDX_IN_IDIF) stores IDIF with index 0 in LMA; osd_check_lma rebuilds with real index, we don't -> same FID on two OSTs | Take if verified: rebuild with tt_index when fid_is_idif && idx 0 && TGT_INDEX known |
| B2 | 68156 | b39fe0036b | llapi_scan_device.3: -EIO wider than documented, -ENOMEM missing | Take |
| B3 | 68156 | b39fe0036b | fid_is_root() in UAPI should return bool | Take |
| C0 | 68159 | 0751092444 | split %LO into its own change | Decline (adilger asked for it in this change) |
| C1 | 68159 | 0751092444 | undecided count only on stderr; add to stats | SKIP (user 10-19: land ASAP; not important -- partial answer is documented and warned on stderr) |
| C2 | 68159 | 0751092444 | llapi_find_device.3 example "every file over a GB" overpromises | Take |
| D1 | 68160 | ab2cf69fe0 | "'MDT0000' is not an MDT or an OST" wording | Take: name the expected form FSNAME-MDT0000 |
| E1 | 68163 | 48a6b6d5c9 | COMMIT_MSG 121-133 answers a review discussion | Take (adilger's 68156 rule: no patch history in messages); rest of the long msg stays |
| F1 | 68288 | 4e053e7953 | lfs-find.1: encrypted-dir limit applies to --fid2path too | Take if verified |
| F2 | 68288 | 4e053e7953 | -printf + --paths/--fid2path refused per target, not once in lfs | Take |
