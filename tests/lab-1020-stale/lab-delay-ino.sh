#!/bin/sh
# Lab only, on top of lab-delay.sh: lab_delay_ino limits the sleep to one
# inode, so a long sleep lands on the object the script is reusing.
set -e
F=$1/lustre/lfu/lfu_ring.c
grep -q lab_delay_ino $F && exit 0
sed -i '/^MODULE_PARM_DESC(lab_delay_us/a\
static unsigned long lab_delay_ino;\
module_param(lab_delay_ino, ulong, 0644);' $F
sed -i 's|^\t\tif (lab_delay_us)$|\t\tif (lab_delay_us \&\& (!lab_delay_ino \|\|\n\t\t\t\t     iops->store(\&env, di) == lab_delay_ino))|' $F
sed -n '/lab_delay_us &&/,+3p' $F
