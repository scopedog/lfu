#!/bin/bash
# Stage 3, as root: sanity 56E* 157* 160A* and conf-sanity 300-304 with two
# MDTs, from the build tree.  Usage: sudo 03-suite.sh ldiskfs|zfs /home/<user>
FS=$1
H=$2
T=$H/lustre-release/lustre/tests
id 500 >/dev/null 2>&1 || useradd -u 500 -m runas
chmod o+x $H
cd $T

export FSTYPE=$FS MDSCOUNT=2 OSTCOUNT=2
bash llmountcleanup.sh > /dev/null 2>&1

# sanity mounts nothing itself
FORMAT=yes bash llmount.sh > /tmp/llmount.log 2>&1 || { tail -20 /tmp/llmount.log; exit 1; }
v=$(lctl get_param -n version 2>/dev/null | head -1)
echo "=== version: $v"
[ -n "$v" ] || { echo "modules not loaded"; exit 1; }
ONLY="56E 157 160A" bash sanity.sh > /tmp/sanity.log 2>&1
echo "sanity rc=$?"
grep -E "^(PASS|FAIL|SKIP) |^sanity: FAIL" /tmp/sanity.log | sed 's/^/  /'

bash llmountcleanup.sh > /dev/null 2>&1
ONLY="300 301 302 303 304" bash conf-sanity.sh > /tmp/conf-sanity.log 2>&1
echo "conf-sanity rc=$?"
grep -E "^(PASS|FAIL|SKIP) |^conf-sanity: FAIL" /tmp/conf-sanity.log | sed 's/^/  /'
bash llmountcleanup.sh > /dev/null 2>&1
echo "STAGE3 DONE"
