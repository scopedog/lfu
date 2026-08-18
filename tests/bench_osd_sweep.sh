#!/bin/bash
# Warm bp × ra × threads sweep for the in-kernel OSD scanner (lfu_par).
#
# Why this exists
# ---------------
# The 2026-08-16 warm curve (docs/measurements/blockparse-2026-08-16.md §3) was measured at
# whatever lfu_ra_blocks happened to be set to -- the default 32 -- and there is
# not a single ra= label in bench-data/2026-08-16/blockparse-warm.txt to prove
# otherwise.  That axis was never swept warm, and it should have been: warm,
# every inode-table block is already in page cache, so each sb_breadahead() is a
# buffer-cache lookup that finds what it wants and accomplishes nothing, on a
# path where lock traffic is already ~a third of the profile.  So the headline
# 17,392,147 obj/s may be understated.
#
# The deeper problem is that lfu_par's report line records dev, private,
# nthreads, chunk and recattr but NOT the three osd_ldiskfs tunables the run
# actually depended on.  Every published row therefore carried a hand-written
# "bp=0"-style label, which is a label that can be wrong.  This script sets each
# tunable, READS IT BACK, and builds the label from the readback, so a row
# cannot claim a configuration it did not run under.
#
# What it does not do
# -------------------
# Cold.  That ritual is different in kind -- unmount everything, drop_caches,
# remount, and take the FIRST pass only, because a second pass is warm by
# definition (docs/measurements/parallel-osd-measured-2026-08-15.md §"Unmount everything").
# Automating it means unmounting a filesystem, which is not something to do
# behind a --flag.  Run cold by hand, as it was run before.
#
# Requires: root, a mounted ldiskfs MDT, the patch stack (parallel-it, rec-attr,
# itable-readahead, itable-blockparse), and lfu_par.ko built from src/kernel.
#
# Usage:
#   tests/bench_osd_sweep.sh [options]
#     --dev NAME        OSD obd device      (default lustre-MDT0000-osd)
#     --ko PATH         lfu_par.ko          (default src/kernel/lfu_par.ko)
#     --ra "LIST"       readahead windows   (default "0 8 16 32 64 128 256")
#     --bp "LIST"       0=iget 1=blockparse (default "1")
#     --threads "LIST"  enumerator threads  (default "1 4")
#     --passes N        passes per row      (default 3, median reported)
#     --chunk N         objects per shard   (default 65536)
#     --no-attr         run with recattr=0
#     --controls        also sweep ra for bp=0, to test whether the iget path's
#                       own 32-block window makes it insensitive to ours
#     --out FILE        tee the result lines to FILE as well as stdout
#     --dry-run         print the matrix and the commands, touch nothing
#     --self-test       check the parser/median/label logic and exit
set -uo pipefail

DEV=lustre-MDT0000-osd
KO=""
RA_LIST="0 8 16 32 64 128 256"
BP_LIST="1"
THREADS="1 4"
PASSES=3
CHUNK=65536
RECATTR=1
CONTROLS=0
OUT=""
DRY=0
SELFTEST=0

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
OSD_PARAMS=/sys/module/osd_ldiskfs/parameters

die() { echo "bench_osd_sweep: $*" >&2; exit 1; }
note() { echo "### $*"; }

while [ $# -gt 0 ]; do
	case "$1" in
	--dev)		DEV=$2; shift 2 ;;
	--ko)		KO=$2; shift 2 ;;
	--ra)		RA_LIST=$2; shift 2 ;;
	--bp)		BP_LIST=$2; shift 2 ;;
	--threads)	THREADS=$2; shift 2 ;;
	--passes)	PASSES=$2; shift 2 ;;
	--chunk)	CHUNK=$2; shift 2 ;;
	--no-attr)	RECATTR=0; shift ;;
	--controls)	CONTROLS=1; shift ;;
	--out)		OUT=$2; shift 2 ;;
	--dry-run)	DRY=1; shift ;;
	--self-test)	SELFTEST=1; shift ;;
	-h|--help)	sed -n '2,50p' "$0"; exit 0 ;;
	*)		die "unknown option '$1' (try --help)" ;;
	esac
done

[ -n "$KO" ] || KO="$ROOT/src/kernel/lfu_par.ko"

# ------------------------------------------------------------------ #
# Parsing lfu_par's report line                                      #
#
# The format is fixed by the pr_info() at the end of lfu_par_run():
#   lfu_par: dev=%s private=%u nthreads=%u chunk=%u recattr=%u objects=%llu
#            attr_ok=%lld fidsum=%016llx attrsum=%016llx chunks=%lld
#            time=%lld.%03llds rate=%llu/s per-thread min=%llu max=%llu err=%d
# Fields are read by name rather than by position so that adding one upstream
# does not silently shift the values this script records.

# field <line> <name> -> the value of name=... , or empty
field() {
	printf '%s\n' "$1" |
		sed -nE "s/.*(^|[[:space:]])$2=([^[:space:]]+).*/\2/p" | head -1
}

# median <n1> <n2> ... -> the middle value by numeric sort.
#
# An even count returns the upper of the two middle values rather than their
# mean, deliberately: every published row is a median of an odd number of
# passes, and inventing a value that no pass produced would make a row
# unverifiable against the raw lines beside it.
median() {
	local n=$#
	[ "$n" -gt 0 ] || { echo 0; return; }
	printf '%s\n' "$@" | sort -n | sed -n "$(( n / 2 + 1 ))p"
}

# ------------------------------------------------------------------ #
# Self-test: everything above, without a kernel                      #

if [ "$SELFTEST" = 1 ]; then
	pass=0; fail=0
	t() {
		if [ "$2" = "$3" ]; then
			pass=$((pass+1)); printf '  PASS %s\n' "$1"
		else
			fail=$((fail+1))
			printf '  FAIL %s: want %s got %s\n' "$1" "$2" "$3"
		fi
	}
	# A real report line, values taken from the 2026-08-16 warm peak row.
	L="[  123.456789] lfu_par: dev=lustre-MDT0000-osd private=1 nthreads=4 chunk=65536 recattr=1 objects=2000097 attr_ok=2000097 fidsum=a589666c4d4f7123 attrsum=fca15e310ea825d8 chunks=67 time=0.115s rate=17392147/s per-thread min=491520 max=520288 err=0"
	t "objects"  2000097            "$(field "$L" objects)"
	t "fidsum"   a589666c4d4f7123   "$(field "$L" fidsum)"
	t "attrsum"  fca15e310ea825d8   "$(field "$L" attrsum)"
	t "chunks"   67                 "$(field "$L" chunks)"
	t "rate"     17392147/s         "$(field "$L" rate)"
	t "err"      0                  "$(field "$L" err)"
	t "nthreads" 4                  "$(field "$L" nthreads)"
	# attr_ok must not be captured by a loose match on "attr"
	t "attr_ok"  2000097            "$(field "$L" attr_ok)"
	# min/max are hyphenated into per-thread; make sure they still resolve
	t "min"      491520             "$(field "$L" min)"
	# A no-attr line has a zero attrsum, which is not an error
	L0="lfu_par: dev=d private=1 nthreads=8 chunk=65536 recattr=0 objects=2000097 attr_ok=0 fidsum=a589666c4d4f7123 attrsum=0000000000000000 chunks=67 time=0.142s rate=14085190/s per-thread min=196608 max=266751 err=0"
	t "noattr attrsum" 0000000000000000 "$(field "$L0" attrsum)"
	t "median odd"  2 "$(median 3 1 2)"
	t "median dup"  5 "$(median 5 5 5)"
	t "median one"  7 "$(median 7)"
	# rate strings sort numerically once /s is stripped
	t "median rates" 12048777 \
	  "$(median 11905339 12048777 12121800)"
	echo
	echo "self-test: passed $pass, failed $fail"
	[ "$fail" = 0 ] || exit 1
	exit 0
fi

# ------------------------------------------------------------------ #
# Preconditions                                                      #

if [ "$DRY" != 1 ]; then
	[ "$(id -u)" = 0 ] || die "must run as root"
	[ -f "$KO" ] || die "lfu_par.ko not found at $KO (build it in src/kernel)"
	[ -d "$OSD_PARAMS" ] || die "$OSD_PARAMS missing -- is osd_ldiskfs loaded?"
	for p in lfu_blockparse lfu_ra_blocks lfu_noverify; do
		[ -w "$OSD_PARAMS/$p" ] ||
			die "$OSD_PARAMS/$p not writable -- patch stack not applied?"
	done
	[ -w /dev/kmsg ] || die "/dev/kmsg not writable"
fi

# ------------------------------------------------------------------ #
# Tunables: set, then read back, and let the readback be the label    #

# Module bool params read back as Y/N, not 1/0.
norm() {
	case "$1" in
	Y|y) echo 1 ;;
	N|n) echo 0 ;;
	*)   echo "$1" ;;
	esac
}

# set_tunable <name> <value> -> echoes the normalised readback
set_tunable() {
	local name=$1 want=$2 path=$OSD_PARAMS/$1 got

	if [ "$DRY" = 1 ]; then
		echo "+ echo $want > $path" >&2
		echo "$want"
		return 0
	fi

	echo "$want" > "$path" || die "cannot write $path"
	got=$(norm "$(cat "$path")")
	# The whole point: never label a row from what we asked for.
	[ "$got" = "$(norm "$want")" ] ||
		die "$name readback is '$got' after writing '$want'"
	echo "$got"
}

# ------------------------------------------------------------------ #
# One pass                                                           #

# run_pass <private> <nthreads> -> the report line, or empty
run_pass() {
	local private=$1 nthreads=$2 marker line

	if [ "$DRY" = 1 ]; then
		echo "+ insmod $KO dev=$DEV nthreads=$nthreads private=$private" \
		     "recattr=$RECATTR chunk=$CHUNK" >&2
		# A plausible line, so --dry-run exercises the parse and label
		# path too.  It mirrors recattr, because a recattr=0 run really
		# does report a zero attrsum and a dry run should not imply
		# otherwise.
		local fake_attrsum=fca15e310ea825d8 fake_attr_ok=2000097
		if [ "$RECATTR" = 0 ]; then
			fake_attrsum=0000000000000000
			fake_attr_ok=0
		fi
		echo "lfu_par: dev=$DEV private=$private nthreads=$nthreads" \
		     "chunk=$CHUNK recattr=$RECATTR objects=2000097" \
		     "attr_ok=$fake_attr_ok fidsum=a589666c4d4f7123" \
		     "attrsum=$fake_attrsum chunks=67 time=0.115s" \
		     "rate=17392147/s per-thread min=491520 max=520288 err=0"
		return 0
	fi

	# lfu_par is one-shot: it does the work in module_init and then returns
	# -ENODEV so it never stays loaded.  insmod therefore "fails" on every
	# successful run, and the summary line in dmesg is the real result.
	rmmod lfu_par 2>/dev/null

	marker="lfu-sweep-$$-${RANDOM}-${SEQ:-0}"
	echo "$marker" > /dev/kmsg

	insmod "$KO" dev="$DEV" nthreads="$nthreads" private="$private" \
		recattr="$RECATTR" chunk="$CHUNK" >/dev/null 2>&1

	# Only look after our own marker, so a slow previous run's line can
	# never be read as this one's.
	line=$(dmesg | sed -n "/$marker/,\$p" | grep -m1 'lfu_par: dev=')
	printf '%s\n' "$line"
}

# ------------------------------------------------------------------ #
# The sweep                                                          #

emit() {
	printf '%s\n' "$1"
	[ -z "$OUT" ] || printf '%s\n' "$1" >> "$OUT"
}

FID_REF=""
ATTR_REF=""
OBJ_REF=""
consistency_bad=0

# check_identity <line> <label>
#
# The invariant every published table leans on: the object set and the
# attributes are identical across every configuration, or the sharding (or the
# block parse) is wrong.  A sweep that does not assert this is just a list of
# numbers.
check_identity() {
	local line=$1 label=$2 obj fid attr

	obj=$(field "$line" objects)
	fid=$(field "$line" fidsum)
	attr=$(field "$line" attrsum)

	if [ -z "$OBJ_REF" ]; then
		OBJ_REF=$obj; FID_REF=$fid; ATTR_REF=$attr
		return 0
	fi
	if [ "$obj" != "$OBJ_REF" ] || [ "$fid" != "$FID_REF" ]; then
		echo "!!! $label: objects/fidsum differ from the first row" \
		     "($obj/$fid vs $OBJ_REF/$FID_REF)" >&2
		consistency_bad=$((consistency_bad+1))
	fi
	# attrsum is only meaningful with recattr=1, and is zero without it
	if [ "$RECATTR" = 1 ] && [ "$attr" != "$ATTR_REF" ]; then
		echo "!!! $label: attrsum differs from the first row" \
		     "($attr vs $ATTR_REF)" >&2
		consistency_bad=$((consistency_bad+1))
	fi
}

nv=$(set_tunable lfu_noverify 1)
note "warm bp x ra x threads sweep -- dev=$DEV recattr=$RECATTR chunk=$CHUNK" \
     "passes=$PASSES noverify=$nv"
note "every row's bp= and ra= are read back from $OSD_PARAMS, not assumed"

# Warm means warm: one throwaway pass to pull the inode table into page cache
# before anything is recorded.  Without this the first measured row is really a
# cold row and reads low, which is the easiest way to publish a wrong curve.
if [ "$DRY" != 1 ]; then
	note "priming page cache (one unrecorded pass)"
	SEQ=prime run_pass 1 4 >/dev/null
fi

bp_sweep="$BP_LIST"
[ "$CONTROLS" = 1 ] && bp_sweep="$BP_LIST 0"

seq_n=0
for bp in $bp_sweep; do
	bp_got=$(set_tunable lfu_blockparse "$bp")
	for ra in $RA_LIST; do
		ra_got=$(set_tunable lfu_ra_blocks "$ra")
		for j in $THREADS; do
			rates=()
			last=""
			for pass in $(seq 1 "$PASSES"); do
				seq_n=$((seq_n+1))
				line=$(SEQ=$seq_n run_pass 1 "$j")
				if [ -z "$line" ]; then
					echo "!!! no report line for" \
					     "bp=$bp_got ra=$ra_got j$j pass $pass" >&2
					continue
				fi
				err=$(field "$line" err)
				[ "$err" = 0 ] ||
					echo "!!! bp=$bp_got ra=$ra_got j$j: err=$err" >&2
				rates+=( "$(field "$line" rate | tr -d '/s')" )
				last=$line
				check_identity "$line" "bp=$bp_got ra=$ra_got j$j"
			done
			[ -n "$last" ] || continue
			emit "WARM bp=$bp_got ra=$ra_got j$j$( \
				[ "$RECATTR" = 0 ] && printf -- -noattr) \
objects=$(field "$last" objects) fidsum=$(field "$last" fidsum) \
attrsum=$(field "$last" attrsum) passes=${#rates[@]} \
rate_median=$(median "${rates[@]}")/s rates=$(IFS=,; echo "${rates[*]}")"
		done
	done
done

# Leave the tunables where a normal build expects them rather than wherever the
# last row of the sweep happened to put them.
if [ "$DRY" != 1 ]; then
	set_tunable lfu_blockparse 1 >/dev/null
	set_tunable lfu_ra_blocks 32 >/dev/null
	set_tunable lfu_noverify 0 >/dev/null
	note "tunables restored to blockparse=1 ra=32 noverify=0"
fi

if [ "$consistency_bad" != 0 ]; then
	echo "FAILED: $consistency_bad row(s) disagreed about the object set" >&2
	exit 1
fi
note "all rows agree: objects=$OBJ_REF fidsum=$FID_REF attrsum=$ATTR_REF"
