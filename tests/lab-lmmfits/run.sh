#!/bin/bash
# Lift find_lmm_fits() from two trees into an ASan harness with a model of
# what llapi_layout_get_by_xattr() reads per composite entry.  $1 = old tree
# rev, $2 = new tree (working dir).  Usage: run.sh <rev> <lustre tree>
T=$2; H=$(mktemp -d)
ex() { python3 -c "
import sys; s=open(sys.argv[1]).read(); a=s.index('static bool find_lmm_fits('); print(s[a:s.index('\n}\n',a)+3])" "$1"; }
git -C $T show $1:lustre/utils/liblustreapi_pfind.c > $H/o.c
ex $H/o.c | sed 's/find_lmm_fits(/fits_old(/' > $H/old.inc
ex $T/lustre/utils/liblustreapi_pfind.c | sed 's/find_lmm_fits(/fits_new(/' > $H/new.inc
cp $(dirname $0)/harness.c $H/h.c
gcc -g -fsanitize=address -o $H/h $H/h.c -I$T/lustre/include/uapi -I$T/include/uapi \
	-I$T/libcfs/include/uapi -I$T/lnet/include/uapi -I$T/lustre/include
for w in 0 1; do for c in 0 1 2 3; do $H/h $w $c 2>&1 | grep -E "fits=|AddressSanitizer" | sed "s/^/$([ $w = 0 ] && echo OLD || echo NEW) /"; done; done
