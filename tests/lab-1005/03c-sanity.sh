#!/bin/bash
# Stage 3c, as root: sanity with every 56E*/160A* subtest named -- ONLY
# reduces "56Ea" to "56", so a bare "56E" matches nothing.  Run after 03.
FS=$1
H=$2
cd $H/lustre-release/lustre/tests
export FSTYPE=$FS MDSCOUNT=2 OSTCOUNT=2
bash llmountcleanup.sh > /dev/null 2>&1
FORMAT=yes bash llmount.sh > /tmp/llmount.log 2>&1 || { tail -20 /tmp/llmount.log; exit 1; }
ONLY="56Ea 56Eaa 56Eab 56Eb 56Ebb 56Ec 56Ed 56Eda 56Edb 56Ef 56Eg 56Eh 56Ei 56Ej 56Ek 56El 56Eea 160Aa 160Ab 160Ac 160Ad 160Ae " bash sanity.sh > /tmp/sanity-c.log 2>&1
echo "sanity rc=$?"
grep -E "^(PASS|FAIL|SKIP) |^sanity: FAIL" /tmp/sanity-c.log | sed 's/^/  /'
bash llmountcleanup.sh > /dev/null 2>&1
echo "STAGE3C DONE"
