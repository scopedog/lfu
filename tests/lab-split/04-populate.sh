#!/bin/bash
# 1,000,000 regular files, 100k in each of d0..d9, made in parallel.
set -e
CM=~/lustre-release/lustre/tests/createmany
M=/mnt/testfs
sudo mkdir -p $M/split/d{0..9}
t0=$(date +%s)
for d in 0 1 2 3 4 5 6 7 8 9; do
	sudo $CM -o $M/split/d$d/f 100000 >/dev/null &
done
wait
sync
echo "populate took $(( $(date +%s) - t0 ))s"
sudo lfs df -i $M | grep MDT
echo "STAGE4 OK"
