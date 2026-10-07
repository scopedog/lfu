# 10-07 AI round: replies (post with the push, not before)

Stack: fix-1007 in ~/lfs-fix-1007, tip `a1007-tip`; edits in rebuild.py here.

| change | comment id | reply |
|---|---|---|
| 68159 | c25be809_3bda963b | Done. |
| 68163 | 963a5de4_b3355c0c | Done. |
| 68163 | 81827f44_c98949dd | Done. Tests lpc_open_access_error with geteuid() != 0 now. |
| 68415 | a55b8afc_98fef952 | Done. |
| 68415 | f74c1dd9_631952dd | Done. Only the moved object's record carries the source now; test8 checks it. |
| 68417 | d740f535_b9571eee | Done. |
| 68417 | d585a1a8_4477d9e7 | Done. |
| 68418 | 72ba260c_81b05286 | 68420 rewrites this paragraph, with both points. |
| 68419 | 23366946_40529039 | Done. |
| 68419 | ec958800_bb6abb23 | Done. |
| 68419 | b06c5a29_b66f78ff | Done. |
| 68419 | 4ccc5b3a_616b761e | Done. A symlink is refused (O_NOFOLLOW, lstat()). |
| 68419 | d382f74a_a86d6760 | Done. |
| 68419 | c5256ba4_96b099bc | Intended; the man pages say so now. |
| 68420 | 9b919579_3ab48756 | Done. |
| 68420 | 62f06a34_5801f3dc | Done. |
| 68420 | 9541f67b_3a4f8bad | Done. |
| 68420 | cf7f229d_bc450d7e | Done. |
| 69443 | eeae8a85_92242f5c | Done. |
| 69443 | c877de12_e409591b | Done. |
| 69443 | a3bd9728_fe489deb | Done. find_cookie_purged(). |

Deferred (user's call): 68419 c5256ba4 -- letting the MDTs whose objects
all resolved advance while only a failing MDT holds back.  Not done: the
stuck state is per-run today, and a per-MDT write changes what a partial
run means.

68810 (OSD series): Artem's el10 build break fixed locally on
lu-20720-el10 (~/lfs-osd-1007); the user replied on Gerrit 10-07.
