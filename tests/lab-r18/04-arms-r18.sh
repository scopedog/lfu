#!/bin/bash
# Round 18's behavioural arms.  Three changes turn a working invocation into
# an error or a different answer, and a refusal that never fires reads exactly
# like a pass -- so each one is asserted directly rather than inferred from a
# green suite.
#
#   68288  --fid2path fails closed when the mount's own fsname cannot be read
#   68419  a cookie that is not a regular file, and a cookie bound to its root
#   68418  fc_d is -1 for a regular file, so -printf %Lc/%Li/%Lo/%Lp changes
#
# Run as root, with the filesystem 11-run-r18.sh left mounted.  A1 runs last:
# it needs the MDT stopped, which the others cannot work around.
set -u
L=${LTREE:-/home/nishida/lustre-r18}
M=${M:-/mnt/lustre}
D=$M/r18arms
pass=0; fail=0
ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $1"; echo "        $2"; fail=$((fail+1)); }

# Mount it here rather than inherit one: A1 stops the filesystem, so a second
# run of this script would otherwise start on the wreckage of the first.
cd $L/lustre/tests
# test-framework.sh is deliberately NOT sourced: it reads unbound variables,
# which under set -u ends this script before its first arm runs.
if ! mount -t lustre | grep -q "on $M "; then
	echo "=== $M is not mounted; formatting and mounting"
	./llmountcleanup.sh >/dev/null 2>&1 || true
	MDSCOUNT=${MDSCOUNT:-2} OSTCOUNT=1 FSTYPE=ldiskfs \
		./llmount.sh > /tmp/llmount-arms.log 2>&1 || true
	mount -t lustre | grep -q "on $M " ||
		{ echo "llmount did not mount $M"; tail -20 /tmp/llmount-arms.log; exit 1; }
fi
rm -rf $D; mkdir -p $D/a $D/b || exit 1

echo "=== lfs: $(lfs --version 2>&1 | head -1)"
echo "=== loaded: $(lctl get_param -n version)"

# --changelog takes a REQUIRED argument, so it is "--changelog MDT --resolve";
# "--changelog --resolve" makes getopt read --resolve as the MDT name, which
# is a silent misparse and not an error.
MDT=$(lctl dl | awk '/ mdt /{print $4}' | sort | head -1)
[ -n "$MDT" ] || { echo "no MDT is up"; exit 1; }
echo "=== MDT: $MDT"
# a changelog user, so --since/--changelog have a source to read
CL=$(lctl --device $MDT changelog_register -n 2>/dev/null)
[ -n "$CL" ] || { echo "no changelog user could be registered on $MDT"; exit 1; }
echo "=== changelog user: ${CL:-<none>}"
lctl set_param -n mdd.*.changelog_mask=ALL >/dev/null 2>&1 || true

########## 68419: a cookie that is not a regular file is refused up front
echo "=== 68419 cookie is not a regular file"
touch $D/a/f1; sync; sleep 1
out=$(lfs find $D/a --since-cookie /tmp --type f 2>&1); rc=$?
if (( rc != 0 )) && grep -qi "not a regular file" <<<"$out"; then
	ok "a directory as a cookie is refused up front"
else
	bad "a directory as a cookie was not refused (rc=$rc)" "$out"
fi
# and it is refused BEFORE the log is scanned: nothing may reach stdout
if grep -q "^$M" <<<"$out"; then
	bad "the refusal printed matches before it refused" "$out"
else
	ok "the refusal printed no matches"
fi

out=$(lfs find $D/a --since-cookie "" --type f 2>&1); rc=$?
(( rc != 0 )) && ok "an empty cookie name is refused" ||
	bad "an empty cookie name was accepted (rc=$rc)" "$out"

########## 68419: a cookie is bound to its search root
echo "=== 68419 cookie bound to its search root"
CK=/tmp/r18.cookie; rm -f $CK
out=$(lfs find $D/a --since-cookie $CK --type f 2>&1); rc=$?
if (( rc == 0 )) && [ -s $CK ]; then
	ok "a first run under a writes the cookie"
	head -2 $CK | sed 's/^/        /'
	out=$(lfs find $D/b --since-cookie $CK --type f 2>&1); rc=$?
	if (( rc != 0 )); then
		ok "the same cookie under a different root is refused"
	else
		bad "a cookie was reused under a different root (rc=$rc)" "$out"
	fi
	out=$(lfs find $D/a --since-cookie $CK --type f 2>&1); rc=$?
	(( rc == 0 )) && ok "and it is still accepted under its own root" ||
		bad "the cookie was refused under its own root (rc=$rc)" "$out"
else
	bad "the first run did not write a cookie (rc=$rc)" "$out"
fi

# two paths with one cookie
out=$(lfs find $D/a $D/b --since-cookie $CK --type f 2>&1); rc=$?
(( rc != 0 )) && ok "two paths with one cookie are refused" ||
	bad "two paths shared one cookie (rc=$rc)" "$out"

########## 68418: fc_d is -1 for a regular file, and -name under
########## --changelog --resolve answers against the recorded name.
##########
########## The directories are pinned to MDT0000.  Under DNE a plain mkdir
########## lands wherever the balance sends it, and the changelog of the MDT
########## this arm reads then holds none of these events -- which reads as
########## "the feature returned nothing", not as "the fixture put the files
########## on the other MDT".  That cost an hour before it was noticed.
echo "=== 68418 -printf %L and -name over --changelog --resolve"
CD=$M/r18cl; rm -rf $CD
lfs mkdir -i 0 $CD && lfs mkdir -i 0 $CD/a && lfs mkdir -i 0 $CD/b || exit 1
CL2=$(lctl --device $MDT changelog_register -n 2>/dev/null)
lctl set_param -n mdd.*.changelog_mask=ALL >/dev/null 2>&1 || true
echo "        changelog user: ${CL2:-<none>}, mask ALL"
touch $CD/a/f2 $CD/a/f3; ln $CD/a/f2 $CD/b/g2; sync; sleep 2
recs=$(lfs changelog $MDT 2>/dev/null | grep -c . || true)
echo "        changelog records: $recs"
if (( recs == 0 )); then
	echo "  SKIP  the changelog is empty; see 160ab/160ad in the sanity run"
else
	out=$(lfs find $CD/a --changelog $MDT --resolve -printf '%Lc|%Li|%Lo|%Lp\n' 2>&1); rc=$?
	if (( rc == 0 )) && [ -n "$out" ]; then
		ok "-printf %Lc/%Li/%Lo/%Lp over a changelog source runs"
		echo "$out" | head -5 | sed 's/^/        /'
	else
		bad "-printf over a changelog source gave nothing (rc=$rc)" "$out"
	fi

	# every object the log names, as the baseline the -name arms narrow
	out=$(lfs find $CD --changelog $MDT --resolve -type f 2>&1); rc=$?
	if (( rc == 0 )) && grep -q "/f2$" <<<"$out" && grep -q "/f3$" <<<"$out"; then
		ok "-type f finds both files through the log"
	else
		bad "-type f did not find both files (rc=$rc)" "$out"
	fi

	# a file with one name: the record names it and so does the resolution
	out=$(lfs find $CD --changelog $MDT --resolve -name f3 2>&1); rc=$?
	(( rc == 0 )) && grep -q "/f3$" <<<"$out" &&
		ok "-name matches a file with one name" ||
		bad "-name f3 did not match (rc=$rc)" "$out"

	# the hardlink: the object is printed under its FIRST name, which is
	# the one fid2path answers with, while the name that MATCHED is the
	# second.  This is 160ad's case and the change's own claim.
	out=$(lfs find $CD --changelog $MDT --resolve -name g2 2>&1); rc=$?
	if (( rc == 0 )) && grep -q "/a/f2$" <<<"$out"; then
		ok "-name g2 matches and prints the recorded name a/f2"
	else
		bad "-name g2 did not answer about a/f2 (rc=$rc)" "$out"
	fi

	# and the other direction, which is where it stops being symmetric.
	# A plain walk matches -name f2; through the log it does not, the
	# HLINK record being the surviving one for that FID.  Reported, not
	# asserted either way: whether that is intended is the user's call.
	out=$(lfs find $CD --changelog $MDT --resolve -name f2 2>&1); rc=$?
	ctl=$(lfs find $CD -name f2 2>&1)
	echo "  NOTE  -name f2 through the log: rc=$rc out='${out:-<empty>}'"
	echo "  NOTE  -name f2 over a plain walk: '${ctl:-<empty>}'"
fi
# the same predicates over a plain walk, as the control -- this one does not
# depend on the changelog at all
out2=$(lfs find $CD/a -printf '%Lc|%Li|%Lo|%Lp\n' 2>&1); rc=$?
(( rc == 0 )) && [ -n "$out2" ] && ok "-printf %L over a plain walk (control)" ||
	bad "-printf over a plain walk failed (rc=$rc)" "$out2"

########## 68288: --fid2path fails closed on a mount it cannot read
echo "=== 68288 --fid2path fails closed (stopping the filesystem)"
# bounded: the teardown can hang on an unmount waiting for recovery, and a
# hung teardown hides every result the arms already produced
cd $L/lustre/tests && timeout 300 ./llmountcleanup.sh >/dev/null 2>&1 || true
DEV=$(ls /tmp/lustre-mdt1 2>/dev/null || ls /tmp/lustre-mdt* 2>/dev/null | head -1)
if [ -n "$DEV" ] && [ -e "$DEV" ]; then
	echo "        target: $DEV"
	out=$($L/lustre/utils/lfind --fid2path /tmp "$DEV" 2>&1); rc=$?
	# Either guard is the change: the point is that it fails closed rather
	# than resolving against a mount it could not match with the target.
	# Which one fires depends on the mount -- /tmp is not a client mount at
	# all, so the open refuses first.  A mount of ANOTHER Lustre filesystem
	# reaches the fsname comparison, which needs two filesystems and is what
	# conf-sanity 166 covers.
	if (( rc != 0 )) &&
	   grep -qiE "cannot find the filesystem of|client mount of the same filesystem" <<<"$out"; then
		ok "--fid2path on a mount that is not this filesystem's is refused"
		echo "        $(head -1 <<<"$out")"
	else
		bad "--fid2path on a non-Lustre mount was not refused (rc=$rc)" "$out"
	fi
	if grep -qE "^\[0x|^/" <<<"$out"; then
		bad "the refusal printed objects before it refused" "$out"
	else
		ok "the refusal printed no objects"
	fi
else
	echo "  SKIP  no MDT device found to scan"
fi

echo "=== arms: $pass passed, $fail failed"
exit $(( fail > 0 ))
