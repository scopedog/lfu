#!/bin/bash
# The oracle: for each scope, every regular file's FID from the walk
# (llapi_scan_namespace) and from the offload (llapi_scan_mount), compared as
# SETS.  A count match can hide a swap; a set diff cannot.
CLI=192.168.122.101
SCOPES=${SCOPES:-"/mnt/lustre /mnt/lustre/bench /mnt/lustre/bench/d3 /mnt/lustre/d0"}
ssh -o BatchMode=yes nishida@$CLI "
for s in $SCOPES; do
  t=\$(echo \$s | tr / _)
  sudo -n /tmp/subfind ns    \$s fids 2>/tmp/o_ns\$t.err    | sort > /tmp/o_ns\$t
  sudo -n /tmp/subfind mount \$s fids 2>/tmp/o_mount\$t.err | sort > /tmp/o_mount\$t
  printf '%-24s walk=%-6s offload=%-6s only-walk=%-4s only-offload=%-4s\n' \$s \
    \$(wc -l < /tmp/o_ns\$t) \$(wc -l < /tmp/o_mount\$t) \
    \$(comm -23 /tmp/o_ns\$t /tmp/o_mount\$t | wc -l) \
    \$(comm -13 /tmp/o_ns\$t /tmp/o_mount\$t | wc -l)
  echo \"    \$(cat /tmp/o_mount\$t.err)\"
done"
