# a1017 replies -- AI round on the 10-14 patchsets

To post WITH the push (gerrit-reply-brevity: "Done." when addressed, a reason
only when declining).  Thread ids are the root comment ids.

| Change | Thread | Reply |
|---|---|---|
| 68156 | 485b1c07_663e0a08 | Done. |
| 68158 | 63979fe1_edbc257c | Done. 68160 adds it back with its first use, llapi_name_verify(). |
| 68158 | 4441713a_bb86dbec | Done. |
| 68159 | fa712d02_eb6ba86f | Done. |
| 68159 | 1e2474be_2b6c6bbf | Done. |
| 68159 | ac196834_d22b8344 | Not changed. find_lmv_rejects() is a few in-memory comparisons, and fc_path is not a walk marker: the --since records of 68417 set it too, so that gate would skip the check there. |
| 68159 | cc0ef9d2_27476a6b | Done. |
| 68160 | 02a10a46_6d2cda51 | Done. |
| 68163 | 7bf7ed99_f24edadf | Done. |
| 68163 | 62de17d3_e446743a | Done. |
| 68288 | 010bc2da_8d1a04ef | Done. |
| 68288 | 3592e59a_a2da22be | Done. |
| 68415 | cc706da5_c17708f9 | Done, the owner moves into 68288. |
| 68415 | 8a0307fa_e005a11c | Done. |
| 68415 | 19270dda_fa62847e | Done. |
| 68415 | fa65a621_7109b0b7 | Done. |
| 68415 | bf6ad7f2_1e6a8337 | Done. |
| 68415 | 6e7bfba4_f341a114 | Done. |
| 68416 | e191222a_da091859 | Done. |
| 68417 | 4205536b_8b56e27e | Done. |
| 68726 | 9954f2b7_fc17ba8b | Done. |
| 69501 | 2019ab14_b1a379e6 | Done. |
| 69502 | 3c794599_c46c0b3f | Done. |
| 69502 | 86500a8b_90ecd953 | Done. |
| 69502 | 94da9534_83ebfc3f | Done. |
| 68726 | 43e4332a_1d7ecc36 | USER DECISION: a sizeof() static_assert in liblustreapi_scan_batch.c would fail the build of whichever of 68726 / 68288 (LLAPI_SCAN_OWNER grows the record) lands second. Right failure, but it ties landing order. |
