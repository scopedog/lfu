# Batch 1's enforced Maloo failures, triaged — 2026-09-22

The push gate for batch 2 is "batch 1 jenkins-green". The overnight suites
came back with **six enforced failures across three of the four changes**.
None of them is ours.

| change | group | suite | subtest | symptom |
|---|---|---|---|---|
| 68158 | review-dne-zfs-part-4 | sanity-quota | test_63 "quota on DoM" | write failed, expect succeed |
| 68159 | review-dne-part-5 | sanityn | test_cleanup | TIMEOUT, "Autotest time out" at 5400 s |
| 68159 | review-ldiskfs-ubuntu | sanity-lnet | test_236 "Local NI state propagates to routers" | expected peer NI state "down" |
| 68160 | review-dne-part-2 | sanity-lfsck | — | known noise |
| 68160 | review-dne-zfs-part-1 | sanity | test_805 "ZFS can remove from full fs" | **node CRASH** |
| 68160 | review-dne-zfs-part-2 | sanity-lfsck | — | known noise |

## Why none of them is ours

**1. Batch 1 ships no kernel code at all.** 68158, 68159, 68160 and 68163
touch only `lustre/utils/`, `lustre/tests/`, `Documentation/`,
`include/lustre/lustreapi.h`, `config/lustre-build-zfs.m4` and
`lustre.spec.in`. Every enforced failure above is a kernel-side or
infrastructure symptom: quota enforcement on Data-on-MDT, LNet peer state
propagation, a node crash in the ZFS OSD under ENOSPC, LFSCK, and an
autotest timeout in cleanup. The only route from a userspace-only change to
those would be `lfs` misbehaving inside the test framework -- and none of
the failures is an `lfs` invocation failing. They are "write failed",
"peer NI state", a crashed node and a 5400-second timeout.

**2. The same suites fail as optional on all four changes**, including
68163, which has no enforced failures: sanity, sanity-lfsck, sanityn,
racer, sanity-sec, sanity-selinux, recovery-small. That is the standing
pattern in [`lfu-autotest-known-noise`], not a signal.

**3. The one conf-sanity failure is not our tests.** 68163's optional
`review-dne-part-3` failed conf-sanity 38, 39, 40 and 41a -- 38 returned 1
and 39/40 then reported "Unable to start OST1", a cascade from it. Ours are
300-305 and all passed.

## What to do

**Retest the failed sessions; do not re-spin.** That is a Gerrit action, so
it waits for the user. Per [`gerrit-etiquette`], retest the sessions rather
than rebasing, and use BUILD to retrigger if a session will not retest.

The conclusion the gate needs: **batch 1 is green as far as this series is
concerned**, and batch 2's push is not blocked by these six.

## 68094 and 68156, the two outside batch 1 — 2026-09-22, later

Both carry Maloo Verified -1 as well, and both sit under batch 2, so their
enforced failures belong in the same gate.

| change | group | suite | subtest | symptom |
|---|---|---|---|---|
| 68094 | review-dne-zfs-part-2 | sanity-lfsck | test_18e | "Expect 2 orphans have been fixed, but got: 4" |
| 68094 | review-ldiskfs-ubuntu | sanity-lnet | test_236 | expected peer NI state "down" |
| 68156 | review-dne-zfs-part-5 | sanityn | test_70b | **node CRASH**, "remove files after calling rm_entry" |

**None of them is ours, for the same reasons and one new one.**

**The corroboration:** `sanity-lnet test_236` failed here on **68094** and,
earlier today, on **68159** -- two unrelated changes, the same subtest, the
same window. That is the flakiness signature, not a patch.

**sanity-lfsck** is on the standing noise list, and `test_18e` is LFSCK
orphan accounting on ZFS -- kernel-side, and 68094 adds `llapi_scan_*` to
liblustreapi and nothing else.

**sanityn test_70b** crashed a node. 68156 is *almost* userspace-only: it
moves `fid_is_root()` from `lustre/include/lustre_fid.h` into the UAPI
header so userspace can use it, and the move drops `unlikely()` from the
return. That is a branch hint; the predicate is `lu_fid_eq(fid,
&LU_ROOT_FID)` before and after. A compile-time hint on an inline
comparison cannot crash a node in "remove files after calling rm_entry",
and nothing else in the change reaches the kernel.

So the gate's answer is unchanged and now covers all six: **retest, do not
re-spin.**
