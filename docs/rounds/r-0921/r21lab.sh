#!/bin/bash
# Round 21's behavioural arms.  A = r0920-tip (unfixed), B = r0921-tip
# (fixed); one build tree, the arms chosen by LD_PRELOAD of that arm's
# liblustreapi, which wins over the binary's RPATH because the SONAME is the
# same.  Each arm logs which library it actually loaded -- an arm that loads
# the other one's lib reads exactly like a pass.
#
#   68094  LLAPI_SCAN_ATTRS gates on OBD_MD_FLFLAGS, not stx_attributes_mask
#   68095  `! --foreign` on an unstriped directory costs no getattr RPC
#   68156  a striped directory's size and blocks are withheld by a device scan
#
# Run as root.
set -u
T=${T:-/home/nishida/lustre-0918}
M=${M:-/mnt/lustre}
D=$M/r21arms
H=/home/nishida
L=/tmp/r21lab
mkdir -p $L
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; [ $# -gt 1 ] && echo "        $2"; fail=$((fail+1)); }

run() {	# run ARM -- command...
	local arm=$1; shift
	LD_PRELOAD=$H/arm$arm/lib/liblustreapi.so.1 "$@"
}

echo "=== which library each arm loads"
for arm in A B; do
	got=$(LD_DEBUG=libs LD_PRELOAD=$H/arm$arm/lib/liblustreapi.so.1 \
	      $H/arm$arm/lfs --version 2>&1 |
	      grep -m1 -o "/[^ ]*liblustreapi.so[^ ]*")
	echo "  arm $arm -> $got"
	case $got in
	*arm$arm*) ;;
	*) echo "  ABORT: arm $arm did not load its own library"; exit 1;;
	esac
done
md5sum $H/armA/lib/liblustreapi.so.1.0.0 $H/armB/lib/liblustreapi.so.1.0.0

cd $T/lustre/tests || exit 1
if ! mount -t lustre | grep -q "on $M "; then
	echo "=== $M is not mounted; formatting and mounting (2 MDTs)"
	./llmountcleanup.sh >/dev/null 2>&1 || true
	MDSCOUNT=2 OSTCOUNT=1 FSTYPE=ldiskfs ./llmount.sh > $L/llmount.log 2>&1 || true
	mount -t lustre | grep -q "on $M " ||
		{ echo "llmount did not mount $M"; tail -20 $L/llmount.log; exit 1; }
fi
echo "=== loaded: $(lctl get_param -n version)"

rm -rf $D; mkdir -p $D/plain || exit 1
for i in $(seq 1 20); do mkdir -p $D/plain/d$i; touch $D/plain/d$i/f; done
$H/armB/lfs setdirstripe -c 2 $D/r21striped ||
	{ echo "cannot make a striped directory"; exit 1; }
touch $D/r21striped/one $D/r21striped/two
touch $D/imm; chattr +i $D/imm 2>/dev/null || echo "  (chattr +i failed)"
sync

########## 68094: the attrs valid bit
echo "=== 68094 LLAPI_SCAN_ATTRS"
for arm in A B; do run $arm $H/scanrec $D > $L/scanrec.$arm 2>&1; done
if diff -u $L/scanrec.A $L/scanrec.B > $L/scanrec.diff; then
	ok "the record is identical A/B on a live MDT (the MDT always answers OBD_MD_FLFLAGS)"
else
	bad "the record differs A/B" "$(head -8 $L/scanrec.diff)"
fi
n=$(awk '$2=="attrs=no"' $L/scanrec.B | wc -l)
t=$(wc -l < $L/scanrec.B)
if [ "$n" = 0 ] && [ "$t" -gt 0 ]; then
	ok "every one of the $t Lustre objects still carries LLAPI_SCAN_ATTRS ($n without)"
else
	bad "$n of $t Lustre objects lost LLAPI_SCAN_ATTRS" "$(awk '$2=="attrs=no"' $L/scanrec.B | head -3)"
fi
# the mask is still applied: an immutable file reports STATX_ATTR_IMMUTABLE
for arm in A B; do
	out=$(run $arm $H/arm$arm/lfs find $D --attrs +i 2>&1)
	if [ "$out" = "$D/imm" ]; then
		ok "arm $arm: --attrs +i finds the immutable file and nothing else"
	else
		bad "arm $arm: --attrs +i answered unexpectedly" "$out"
	fi
done
# off Lustre nothing declares flags, so the bit must be clear in both arms
mkdir -p /tmp/r21posix/sub && touch /tmp/r21posix/sub/f
for arm in A B; do run $arm $H/scanrec /tmp/r21posix > $L/posix.$arm 2>&1; done
if ! grep -q "attrs=yes" $L/posix.B; then
	ok "off Lustre no object claims attributes (arm B)"
else
	bad "an object off Lustre claims attributes in arm B" "$(grep -m2 attrs=yes $L/posix.B)"
fi

########## 68095: `! --foreign` and the getattr RPC
echo "=== 68095 ! --foreign getattr RPCs"
getattrs() { lctl get_param -n mdc.*.md_stats mdc.*.stats 2>/dev/null |
	     awk '/^mds_getattr /{s+=$2} END{print s+0}'; }
for arm in A B; do
	lctl set_param -n mdc.*.md_stats=clear mdc.*.stats=clear >/dev/null 2>&1
	before=$(getattrs)
	run $arm $H/arm$arm/lfs find $D/plain ! --foreign > $L/foreign.$arm 2>&1
	after=$(getattrs)
	echo "$((after - before))" > $L/foreign.rpc.$arm
	echo "  arm $arm: $(wc -l < $L/foreign.$arm) objects, $((after - before)) mds_getattr"
done
if diff -q $L/foreign.A $L/foreign.B >/dev/null; then
	ok "the answer is unchanged A/B ($(wc -l < $L/foreign.B) paths)"
else
	bad "the answer changed A/B" "$(diff $L/foreign.A $L/foreign.B | head -5)"
fi
ra=$(cat $L/foreign.rpc.A); rb=$(cat $L/foreign.rpc.B)
if [ "$rb" -lt "$ra" ]; then
	ok "arm B asks for fewer getattrs: $rb vs $ra"
else
	bad "arm B did not drop any getattr: $rb vs $ra"
fi
# -printf still gathers: the attributes it prints are this object's
for arm in A B; do
	lctl set_param -n mdc.*.md_stats=clear mdc.*.stats=clear >/dev/null 2>&1
	before=$(getattrs)
	run $arm $H/arm$arm/lfs find $D/plain ! --foreign -printf '%p %s\n' \
	    > $L/printf.$arm 2>&1
	after=$(getattrs)
	echo "  arm $arm -printf: $((after - before)) mds_getattr"
	echo $((after - before)) > $L/printf.rpc.$arm
done
if diff -q $L/printf.A $L/printf.B >/dev/null; then
	ok "-printf prints the same thing A/B"
else
	bad "-printf output changed A/B" "$(diff $L/printf.A $L/printf.B | head -5)"
fi
if [ "$(cat $L/printf.rpc.B)" = "$(cat $L/printf.rpc.A)" ]; then
	ok "-printf still pays the getattr in both arms ($(cat $L/printf.rpc.B))"
else
	bad "-printf's RPC count changed" "A=$(cat $L/printf.rpc.A) B=$(cat $L/printf.rpc.B)"
fi

########## 68156: a striped directory from a device scan
echo "=== 68156 striped directory size from a device scan"
echo "--- what a walk reports for it (the oracle)"
for arm in A B; do
	run $arm $H/scanrec $D 2>/dev/null | grep r21striped > $L/walkstriped.$arm
done
cat $L/walkstriped.B | sed 's/^/  /'
if grep -q "size=unknown" $L/walkstriped.B && grep -q "blocks=unknown" $L/walkstriped.B; then
	ok "a walk answers 'not known' for the striped directory"
else
	bad "a walk answered a size for the striped directory" "$(cat $L/walkstriped.B)"
fi
