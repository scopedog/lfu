# Lab scripts — conf-sanity test_166 on two nodes (LU-20637)

The single-node labs cannot see the bug this lab was built for: test_166 ran
`lfind --fid2path $MOUNT` on the MDS, and on one node `$MOUNT` happens to
exist there. Autotest has the MDS and the client on different nodes, where it
does not.

Two `c3-standard-8` rocky-linux-9 instances, `lfu-166-srv` (MGS+MDT+OST) and
`lfu-166-cli` (client, and the conf-sanity runner):

| script | where | what it does |
|---|---|---|
| `01-prereq.sh` | both | repos and build prerequisites; copied from `tests/lab-scan/` |
| `02-build.sh`  | both | the ten-patch series on `5afbab284e`, configure, build, install. Run on both so the versions and the `lustre/tests` directory match |
| `03-ssh.sh`    | client | root ssh key for the runner; the pubkey goes in the server's `/root/.ssh/authorized_keys` |
| `04-run166.sh` | client | `mds_HOST`/`ost_HOST`/`mgs_HOST` at the server, then conf-sanity `ONLY=166` |

Result: [`bench-data/2026-08-25/t166-two-node-lab.txt`](../../bench-data/2026-08-25/t166-two-node-lab.txt)
— FAIL before the fix with autotest's exact message, PASS after.

Three things that cost time here and are not in the single-node recipes:

- **Direct ssh to the instances does not work from this machine; IAP does.**
  Every `gcloud compute ssh` and `scp` needs `--tunnel-through-iap`.
- **GCP images ship `PermitRootLogin no`**, so test-framework's root-to-root
  ssh fails after the key is installed, with `Server accepts key` followed by
  `Permission denied`. Drop a `PermitRootLogin prohibit-password` file in
  `/etc/ssh/sshd_config.d/` on both nodes and reload sshd.
- **The tree lives in the login user's home**, not root's — `02-build.sh`
  builds as `nishida`, so `04-run166.sh` runs conf-sanity out of
  `/home/nishida/lustre-release` under sudo and has to `chmod o+x` the path.
