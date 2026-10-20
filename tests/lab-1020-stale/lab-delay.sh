#!/bin/sh
# Lab only, never committed: lfu.ko's lab_delay_us, a sleep after next()
# and before the record is built, which widens the gap between the
# attribute copy and the xattr reads.  Usage: lab-delay.sh <tree>
set -e
F=$1/lustre/lfu/lfu_ring.c
grep -q lab_delay_us $F && exit 0
sed -i '/^static bool private_it = true;/a\
static unsigned int lab_delay_us;\
module_param(lab_delay_us, uint, 0644);\
MODULE_PARM_DESC(lab_delay_us, "LAB ONLY: sleep between next() and the xattr reads");' $F
sed -i 's|^\t\tr->st.ls_seen++;$|\t\tr->st.ls_seen++;\n\t\tif (lab_delay_us)\n\t\t\tusleep_range(lab_delay_us, lab_delay_us + 10);|' $F
grep -c lab_delay_us $F
