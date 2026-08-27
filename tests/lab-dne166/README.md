# Lab scripts — conf-sanity test_166 on a DNE filesystem (LU-20637)

The lab that finds the bug the other two could not. `tests/lab-166/` was built
for the MDS-is-not-a-client failure and has **one MDT**; the single-node lab has
one too. `review-dne-subtest-change` is **DNE**, and the failure is a DNE
placement bug, so neither could ever see it.

Two `c3-standard-8` rocky-linux-9 instances, `lfu-dne-srv` (MGS + **4 MDTs** +
OST) and `lfu-dne-cli` (client, and the conf-sanity runner).

| script | where | what it does |
|---|---|---|
| `01-prereq.sh` | both | repos and build prerequisites; unchanged from `lab-166/` |
| `02-build.sh`  | both | the series on `5afbab284e`, configure, build, install |
| `03-ssh.sh`    | client | root ssh key; the pubkey goes on **both** nodes |
| `04b-probe.sh` | client | where does a plain `mkdir` under the root actually land? |
| `05-arms.sh`   | client | `ARM=pre` (bug restored) and `ARM=post` (fix), `ONLY_REPEAT=4` |

Result: [`bench-data/2026-08-27/dne166-lab.txt`](../../bench-data/2026-08-27/dne166-lab.txt)
— pre-fix **PASS then FAIL** with autotest's exact message, post-fix **4/4 PASS**.

## The two things this lab taught

**`MDSCOUNT=4` is the whole configuration.** A stock DNE filesystem already
ships a ROOT default LMV (`lmv_stripe_offset: -1`, `lmv_max_inherit_rr: 3`), so
plain mkdirs under the root round-robin MDT0,1,2,3 with **no** configuration
from the test framework or from autotest. Three runs in four place the test
directory off MDT0000. Nothing has to be rigged to reproduce this — which was
worth measuring rather than assuming, because had it needed rigging, the
reproduction would have proved much less.

**`ONLY_REPEAT` is how `review-dne-subtest-change` runs a changed subtest**, and
it is what exposed the bug: iteration 1 lands on MDT0000 and passes, iteration 2
lands on MDT0001 and fails. A single run is a coin toss — which is exactly why
the Janitor's full `conf-sanity4@ldiskfs+DNE` chunk passed on the same patchset
that Maloo failed. **Use `ONLY_REPEAT` for any new test, not one run.**

## Traps, beyond the ones in `lab-166/README.md`

- **`llmount.sh` exits non-zero with `hostname contains invalid characters`**
  *after* mounting everything successfully. The message is not in the Lustre
  tree. Check `/proc/mounts` rather than trusting the exit status — a `set -e`
  handler on it aborts a lab whose filesystem is fine.
- **test-framework stops repeating after a failure**, so `ONLY_REPEAT=4` reports
  2 iterations when the second fails. That is not a truncated run; autotest's
  session shows the same two.
