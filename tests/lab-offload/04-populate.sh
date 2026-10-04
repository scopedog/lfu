#!/bin/bash
# The 2026-09-10 fixture's shape: 87,944 regular files.
#   /bench      87,894 under d0..d9 (99.9%), d3 = 10,000 (11.4%)
#   /d0             50 (0.06%)
set -e
CM=~/lustre-release/lustre/tests/createmany
M=/mnt/testfs
sudo mkdir -p $M/bench/d{0..9} $M/d0
for d in 0 1 2 4 5 6 7 8 9; do
	n=8655; [ $d = 9 ] && n=8654
	sudo $CM -o $M/bench/d$d/f $n >/dev/null
done
sudo $CM -o $M/bench/d3/f 10000 >/dev/null
sudo $CM -o $M/d0/f 50 >/dev/null
sync
for s in "" bench bench/d3 d0; do
	printf "%-10s %s\n" "/$s" "$(sudo find $M/$s -type f | wc -l)"
done
echo "STAGE4 OK"
