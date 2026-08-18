#!/bin/bash
# Stage 5: run the consumer against the mounted client and check the parts of
# the contract a compile cannot: does it see what `lfs find` sees, is the
# answer independent of thread count, does depth limit, does a callback stop
# the scan, and is the validity mask actually populated.
set -e
cd ~
R=/mnt/testfs
L=~/lustre-release
FAIL=0
ck() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1: '$2' != '$3'"; FAIL=1; fi; }

gcc -O2 -Wall -o ~/scan_test ~/scan_test.c \
	-I$L/include -I$L/include/uapi \
	-L$L/lustre/utils/.libs -llustreapi \
	-Wl,-rpath,$L/lustre/utils/.libs
echo "=== built"

echo "=== 1. one record per object, and what is in it"
~/scan_test $R > ~/scan1.out 2> ~/scan1.err
head -12 ~/scan1.out
cat ~/scan1.err

echo "=== 2. FID set vs lfs find + lfs path2fid"
sudo lfs find $R > ~/find.paths 2>/dev/null
: > ~/find.fids
while read -r p; do
	f=$(sudo lfs path2fid "$p" 2>/dev/null) || continue
	echo "${f//[\[\]]/}" >> ~/find.fids
done < ~/find.paths
awk '{print $1}' ~/scan1.out | tr -d '[]' | sort -u > ~/scan.fids.s
sort -u ~/find.fids > ~/find.fids.s
echo "  lfs find objects : $(wc -l < ~/find.fids.s)"
echo "  scanner objects  : $(wc -l < ~/scan.fids.s)"
MISS=$(comm -23 ~/find.fids.s ~/scan.fids.s | wc -l)
EXTRA=$(comm -13 ~/find.fids.s ~/scan.fids.s | wc -l)
ck "no objects missed" "$MISS" "0"
ck "no extra objects"  "$EXTRA" "0"
if [ "$MISS" != 0 ]; then echo "  missed:"; comm -23 ~/find.fids.s ~/scan.fids.s | head; fi
if [ "$EXTRA" != 0 ]; then echo "  extra:"; comm -13 ~/find.fids.s ~/scan.fids.s | head; fi

echo "=== 3. thread count does not change the answer"
for T in 1 2 4 8; do
	~/scan_test $R $T 2>/dev/null | awk '{print $1}' | tr -d '[]' | sort -u > ~/scan.t$T
done
for T in 2 4 8; do
	ck "-j $T identical to -j 1" "$(diff -q ~/scan.t1 ~/scan.t$T >/dev/null && echo same || echo differs)" "same"
done

echo "=== 4. max_depth limits the descent"
D1=$(~/scan_test $R 1 1 2>/dev/null | wc -l)
D2=$(~/scan_test $R 1 2 2>/dev/null | wc -l)
DA=$(wc -l < ~/scan1.out)
echo "  depth 1: $D1   depth 2: $D2   unlimited: $DA"
ck "depth 1 < depth 2" "$([ "$D1" -lt "$D2" ] && echo yes || echo no)" "yes"
ck "depth 2 < unlimited" "$([ "$D2" -lt "$DA" ] && echo yes || echo no)" "yes"

echo "=== 5. a callback that stops the scan"
set +e
~/scan_test $R 1 0 3 > ~/stop.out 2> ~/stop.err
RC=$?
set -e
echo "  $(cat ~/stop.err)"
ck "callback return reaches the caller" "$RC" "42"
ck "stopped at the third record" "$(wc -l < ~/stop.out)" "3"

echo "=== 6. the validity mask is populated, not blank"
BLANK=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^valid=/) print $i}' ~/scan1.out | grep -c "valid=0x0$" || true)
ck "no record with an empty valid mask" "$BLANK" "0"
echo "  a record's mask: $(awk '{for(i=1;i<=NF;i++) if($i ~ /^valid=/) {print $i; exit}}' ~/scan1.out)"
echo "  records with a layout: $(grep -c 'lmm=yes' ~/scan1.out || true) of $DA"
echo "  distinct record sizes: $(awk '{for(i=1;i<=NF;i++) if($i ~ /^recsz=/) print $i}' ~/scan1.out | sort -u | tr '\n' ' ')"

echo "=== 7. bad arguments are refused"
set +e
~/scan_test /nonexistent-path-xyz > /dev/null 2>~/bad.err; BRC=$?
set -e
echo "  $(cat ~/bad.err)"
ck "a missing path is an error, not a crash" "$([ $BRC -ne 0 ] && echo yes || echo no)" "yes"

echo "=== 8. the demand mask: TYPE-only asks for no ioctl"
SCAN_WANT=4000 ~/scan_test $R > ~/want.out 2> ~/want.err
cat ~/want.err
# every non-root record should carry exactly TYPE; root has no dirent, so 0
NONTYPE=$(grep -v " $R " ~/want.out | awk '{for(i=1;i<=NF;i++) if($i ~ /^valid=/) print $i}' | grep -vc "valid=0x4000$" || true)
ck "TYPE-only records carry only TYPE" "$NONTYPE" "0"
ck "TYPE-only still sees every object" "$(wc -l < ~/want.out)" "$DA"
# and no FID was fetched: every FID prints as zero
# DFID prints seq with %#llx, so a zero FID is [0:0x0:0x0], not [0x0:...]
ck "no FID fetched under TYPE-only" "$(grep -vc '^\[0:0x0:0x0\]' ~/want.out || true)" "0"

echo "=== 9. the pre-filter: name glob before any I/O"
SCAN_NAME='*.txt' ~/scan_test $R > ~/pre.out 2> ~/pre.err
cat ~/pre.err
TXT=$(sudo lfs find $R -name '*.txt' | wc -l)
ck "pre-filter delivers exactly the *.txt objects" "$(wc -l < ~/pre.out)" "$TXT"
NOFID=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^valid=/) {v=strtonum(substr($i,7)); if(!and(v,1)) n++}} END{print n+0}' ~/pre.out)
ck "delivered records are fully gathered (FID present)" "$NOFID" "0"
ck "pre-filter never saw a gathered field" "$(grep -c 'prefilter saw' ~/pre.err || true)" "0"
ck "everything else was filtered, not lost" "$(( $(wc -l < ~/pre.out) + $(sed -n 's/.*filtered=\([0-9]*\).*/\1/p' ~/pre.err) ))" "$DA"

echo "=== 10. a stop really stops, including with threads and work left"
# The traversal only abandons a walk on a negative callback return when
# fp_stop_on_error is set; otherwise it records it and carries on, and
# other worker threads never hear about it.  So the scanner enforces the
# stop itself.  With 300+ objects and a stop after 5 -- past the root, so
# the traversal is inside a directory listing with entries left -- anything
# close to the full count means the stop was ignored.  (A stop on the root
# alone proves nothing: the traversal never opens the root either way.)
for T in 1 4; do
	set +e
	SCAN_QUIET=1 ~/scan_test $R $T 0 5 > /dev/null 2> ~/stopT$T.err
	RC=$?
	set -e
	N=$(sed -n 's/.*scanned=\([0-9]*\).*/\1/p' ~/stopT$T.err)
	echo "  -j $T: $(cat ~/stopT$T.err)"
	ck "-j $T: consumer's value returned" "$RC" "42"
	ck "-j $T: at most 5+threads records after a stop-after-5 (of $DA)" "$([ "$N" -le $((5 + T)) ] && echo yes || echo no)" "yes"
done

echo
[ $FAIL -eq 0 ] && echo "STAGE5 OK" || { echo "STAGE5 FAILED"; exit 1; }
