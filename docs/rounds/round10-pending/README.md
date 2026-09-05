# Queued for the next patchset (round 10)

Six round-9 review points that are **not** in the patchsets pushed on
2026-08-25. Their Gerrit threads are deliberately left **unresolved**, and each
reply says the fix is in the tree for the next patchset. Do not resolve them
until the push.

`round10-code.patch` applies to `lu-20603-scan-api`; the three `msg-*.txt` are
whole commit messages.

| Change | Point | Where |
|---|---|---|
| 68094 | `sr_parent_fd` is -1 above one thread, and the man page pointed consumers at it | `llapi_scan_namespace.3` |
| 68156 | `SOM_FL_STRICT` is a real size: set SIZE/BLOCKS, keep LAZY_\* for LAZY and STALE | `liblustreapi_scan_device.c` |
| 68156 | the epoch-bits comment claimed a per-field test the code does not make | `libscan_ldiskfs.c` |
| 68157 | the message does not mention the dropped descriptor write-back | `msg-68157.txt` |
| 68158 | "byte-identical" does not cover the `--foreign` control-flow edit | `msg-68158.txt` |
| 68158 | `stopped`, `pathstartp`, `pathendp` are written at entry now | `lfs_find_parse.c/.h` |
| 68163 | the message does not account for the `lustre.spec.in` churn | `msg-68163.txt` |

Also here, already replied as done and **not** pending: `fc_mnt_fd` named in the
`find_ctx` trap comment (68288).
