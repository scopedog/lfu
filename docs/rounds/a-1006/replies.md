# Replies for the 10-06 AI round (post with the push, on the PS each was written on)

Keyed by the first 8 chars of the comment id. Brief per gerrit-reply-brevity.

| change | PS | id | reply | resolve |
|---|---|---|---|---|
| 68157 | 31 | 9732716d | Done. | yes |
| 68159 | 28 | 52a8b609 | Done. | yes |
| 68159 | 28 | 7aeb3e02 | Kept undecided for both forms. A walk is told project id 0 for such an inode, so `! --projid 0` would not match there. `! -btime` matches because a walk has no birth time for it either. The comment and the commit message now say so. | yes |
| 68159 | 28 | 54fdb4e7 | Done. | yes |
| 68163 | 28 | d2330bac | Done. spa_evict_all() after kernel_init() drops whatever any cache file loaded. | yes |
| 68415 | 20 | 836a7efb | Done. 56Eea gives the directory a default layout on MDT0. | yes |
| 68417 | 13 | 3409dc49 | Done. | yes |
| 68417 | 13 | 67c5ba25 | The time forms are in 68420, which carries the man page changes. The example is added there. | yes |
| 68417 | 13 | ca9cd3af | Done. | yes |
| 68417 | 13 | 638d3e6f | Done. | yes |
| 68418 | 13 | df8a8758 | Done. | yes |
| 68418 | 13 | 63a09990 | Done. | yes |
| 68418 | 13 | 6d4a8d3d | Done. | yes |
| 68418 | 13 | 92fdfa8f | Done. | yes |

Not answered (style, per the user's 10-05 choice): 68415 6a004a15 (56Eea
naming/placement). wc-checkpatch style items: not answered, as before.
