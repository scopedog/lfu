#!/bin/bash
# The lreview fix round, checked against the walk.  Runs on the client of the
# DNE lab after 04-dne-populate.sh.  $1 = MGS IP.  Mutations are undone.
S0=$1; M=/mnt/testfs; F=/mnt/fset; P="-mtime -30"
bad=0
cmp1() {	# label, then lfs find args (the path first)
	local l=$1; shift
	local w o c
	w=$(sudo lfs find "$@" --no-offload 2>/dev/null | sort | md5sum)
	o=$(sudo lfs find "$@" --offload 2>/tmp/e | sort | md5sum)
	c=$(sudo lfs find "$@" --offload 2>/dev/null | wc -l)
	if [ "$w" = "$o" ]; then echo "SAME  n=$c  $l"
	else echo "DIFF  $l: $*"; bad=1
	     diff <(sudo lfs find "$@" --no-offload 2>/dev/null | sort) <(sudo lfs find "$@" --offload 2>/dev/null | sort) | head -6
	fi
	[ -s /tmp/e ] && echo "      stderr: $(head -c 200 /tmp/e)"
}
echo "== hard links (same dir, cross-dir, cross-MDT)"
sudo ln $M/d0/f1 $M/d0/f1b
sudo ln $M/bench/d1/f0 $M/bench/d7/hl0
sudo ln $M/x/y/f0 $M/d0/hlx
cmp1 "root, all files" $M -type f $P
cmp1 "-name hl*" $M -name 'hl*' $P
cmp1 "-name f0 (one name of a linked file)" $M -name f0 $P
cmp1 "! -name f* -type f" $M ! -name 'f*' -type f $P
cmp1 "subtree bench/d7 (holds a link)" $M/bench/d7 $P
cmp1 "subtree d0" $M/d0 $P
cmp1 "subtree x (MDT1 -> MDT0 chain)" $M/x $P
cmp1 "-type d" $M -type d $P
cmp1 "-name testfs (the root itself)" $M -name testfs $P
cmp1 "-name bench (a subtree root)" $M/bench -name bench $P
cmp1 "-name d3 under bench" $M/bench -name 'd*' -type d $P
echo "== fileset mount of /testfs/bench"
sudo mkdir -p $F
sudo mount -t lustre $S0@tcp:/testfs/bench $F && echo mounted
cmp1 "fileset root" $F $P
cmp1 "fileset subdir d3 (striped)" $F/d3 $P
cmp1 "fileset subdir d7, -name hl0" $F/d7 -name 'hl*' $P
cmp1 "fileset -type d" $F -type d $P
sudo umount $F
echo "== deferred names: move bench/d2 under a new zz/yy"
sudo mkdir -p $M/zz/yy && sudo mv $M/bench/d2 $M/zz/yy/
cmp1 "root after move" $M -type f $P
cmp1 "subtree zz" $M/zz $P
sudo mv $M/zz/yy/d2 $M/bench/ && sudo rmdir $M/zz/yy $M/zz
echo "== auto fallback is quiet: MDT1 inactive on this client"
sudo lctl set_param -n mdc.testfs-MDT0001-mdc-*.active=0 >/dev/null 2>&1 || \
	sudo lctl --device $(sudo lctl dl | awk '/MDT0001-mdc/{print $1; exit}') deactivate
sudo lfs find $M -uid 0 -type f >/dev/null 2>/tmp/auto.err; echo "auto rc=$? stderr: [$(grep -c 'skipped it\|INACTIVE\|predates' /tmp/auto.err) scan messages] $(head -c 160 /tmp/auto.err)"
sudo lfs find $M -uid 0 -type f --offload >/dev/null 2>/tmp/f.err; echo "forced rc=$? stderr: $(head -c 160 /tmp/f.err)"
sudo lctl set_param -n mdc.testfs-MDT0001-mdc-*.active=1 >/dev/null 2>&1 || \
	sudo lctl --device $(sudo lctl dl | awk '/MDT0001-mdc/{print $1; exit}') activate
sleep 3
echo "== --offload with a layout option fails before scanning"
TIMEFORMAT=%3R; { time sudo lfs find $M --offload --stripe-count 1 -type f >/dev/null 2>/tmp/s.err; } 2>/tmp/t; echo "rc=$? in $(cat /tmp/t)s: $(head -c 160 /tmp/s.err)"
echo "== workers: one MDT-count cap (clones with --threads 16)"
sudo strace -f -e trace=clone,clone3 -o /tmp/st lfs find $M --offload --threads 16 -uid 4242 >/dev/null; echo "clones $(grep -c clone /tmp/st) (2 MDTs)"
echo "== undo links"
sudo rm $M/d0/f1b $M/bench/d7/hl0 $M/d0/hlx
echo "files: $(sudo find $M -type f | wc -l)"
[ $bad = 0 ] && echo "ALL SAME" || echo "ORACLE FAILED"
