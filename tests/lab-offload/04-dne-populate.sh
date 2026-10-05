#!/bin/bash
# The 09-10 shape spread over two MDTs, plus the cross-MDT cases:
#   bench (MDT0): d0-d2, d4 on MDT0; d5-d9 remote on MDT1; d3 striped over both
#   d0 (MDT0) 50 files; x (MDT1) / y (MDT0) 100 files: a chain across MDTs
set -e
CM=~/lustre-release/lustre/tests/createmany; M=/mnt/testfs
sudo lfs mkdir -i 0 $M/bench
for d in 0 1 2 4; do sudo lfs mkdir -i 0 $M/bench/d$d; done
for d in 5 6 7 8 9; do sudo lfs mkdir -i 1 $M/bench/d$d; done
sudo lfs mkdir -c 2 $M/bench/d3
sudo lfs mkdir -i 0 $M/d0
sudo lfs mkdir -i 1 $M/x; sudo lfs mkdir -i 0 $M/x/y
for d in 0 1 2 4 5 6 7 8 9; do n=8655; [ $d = 9 ] && n=8654; sudo $CM -o $M/bench/d$d/f $n >/dev/null; done
sudo $CM -o $M/bench/d3/f 10000 >/dev/null
sudo $CM -o $M/d0/f 50 >/dev/null
sudo $CM -o $M/x/y/f 100 >/dev/null
sync
for s in "" bench bench/d3 d0 x; do printf "%-10s %s\n" "/$s" "$(sudo find $M/$s -type f | wc -l)"; done
sudo lfs df -i $M | grep MDT
lfs getdirstripe $M/bench/d3 | head -4
echo "STAGE4 OK"
