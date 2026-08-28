#!/bin/bash
# Instrument the --changelog --resolve -size path, run the size probe, revert.
set -e
L=${LTREE:-/home/nishida/lustre-160ac}
P=$L/lustre/utils/liblustreapi_pfind.c
cd $L
git checkout -- lustre/utils/liblustreapi_pfind.c
python3 /home/nishida/dbg-resolve.py "$P"
make -j"$(nproc)" -C $L/lustre/utils >/tmp/dbg-make.log 2>&1 ||
	{ echo BUILD FAILED; grep -nE "error:" /tmp/dbg-make.log | head -20; \
	  cd $L && git checkout -- lustre/utils/liblustreapi_pfind.c; exit 1; }
sudo make -C $L/lustre/utils install >/dev/null 2>&1
sudo ldconfig
echo "=== instrumented build installed"
bash /home/nishida/06-sizeprobe.sh 2>&1 | grep -E "DBG|===|/mnt/lustre|could not|empty above" | head -40
cd $L && git checkout -- lustre/utils/liblustreapi_pfind.c
echo "DBG RUN DONE (source reverted)"
