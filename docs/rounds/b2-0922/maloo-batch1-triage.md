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
