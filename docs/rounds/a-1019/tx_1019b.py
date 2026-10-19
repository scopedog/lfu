# a-1019 #10 (68419): a DNE block in sanity 160Ac -- each MDT keeps its own
# cookie anchor, and a --changelog run over one MDT keeps the other's line.
# Applied by forktx4.py from 68419 up; only fork-1014 holds 68419.
HITS = {}
SAN = 'lustre/tests/sanity.sh'

R = {
    ('dne', SAN): (
        '''	grep -q "/kept$" <<< "$out" ||
		error "the run after an empty one missed kept: $out"

	rm -rf $DIR/$tdir
''',
        '''	grep -q "/kept$" <<< "$out" ||
		error "the run after an empty one missed kept: $out"

	# Each MDT keeps its own anchor, and a run that reads only one MDT
	# writes the other MDT's line back as it was
	if (( MDSCOUNT > 1 )); then
		local ckd=$ck.dne
		local a0
		local a1

		stack_trap "rm -f $ckd"
		$LFS mkdir -i 1 $DIR/$tdir/m1 || error "mkdir m1 failed"
		$LFS find $DIR/$tdir --since-cookie $ckd -type f > /dev/null ||
			error "the first DNE run failed"
		a0=$(grep "^$FSNAME-MDT0000 " $ckd) ||
			error "no MDT0000 line: $(cat $ckd)"
		a1=$(grep "^$FSNAME-MDT0001 " $ckd) ||
			error "no MDT0001 line: $(cat $ckd)"

		touch $DIR/$tdir/m1/d1 || error "touch m1/d1 failed"
		sync; sleep 2
		out=$($LFS find $DIR/$tdir --since-cookie $ckd -type f) ||
			error "the run after m1/d1 failed"
		[[ "$out" == "$DIR/$tdir/m1/d1" ]] ||
			error "the run after m1/d1 returned '$out'"
		grep -qFx "$a0" $ckd ||
			error "MDT0000 moved with no new record: $(cat $ckd)"
		grep -qFx "$a1" $ckd &&
			error "MDT0001 did not move past m1/d1: $(cat $ckd)"
		a1=$(grep "^$FSNAME-MDT0001 " $ckd)

		touch $DIR/$tdir/d0 $DIR/$tdir/m1/d2 || error "touch failed"
		sync; sleep 2
		out=$($LFS find $DIR/$tdir --changelog $FSNAME-MDT0001 \\
		      --resolve --since-cookie $ckd -type f) ||
			error "the MDT0001 run failed"
		[[ "$out" == "$DIR/$tdir/m1/d2" ]] ||
			error "the MDT0001 run returned '$out'"
		grep -qFx "$a0" $ckd ||
			error "the MDT0001 run moved MDT0000: $(cat $ckd)"
		grep -qFx "$a1" $ckd &&
			error "the MDT0001 run did not move it: $(cat $ckd)"

		# MDT0000's anchor is still before d0, MDT0001's is past m1/d2
		out=$($LFS find $DIR/$tdir --since-cookie $ckd -type f) ||
			error "the run after the MDT0001 run failed"
		[[ "$out" == "$DIR/$tdir/d0" ]] ||
			error "the run after the MDT0001 run returned '$out'"
	fi

	rm -rf $DIR/$tdir
'''),
}

M = {
    'dne': (
        '''next run warns and still finds the record made after the purge.
''',
        '''next run warns and still finds the record made after the purge.

With more than one MDT, 160Ac puts files on MDT0001 too and checks that
each MDT keeps its own anchor: a run that finds a new file on MDT0001
moves only that MDT's line, and a --changelog run over MDT0001 writes
MDT0000's line back as it was, so the next run still finds the file
made on MDT0000.
'''),
}


def fn(path, s, subj):
    for (tag, p), (o, n) in R.items():
        if p != path or o not in s:
            continue
        assert s.count(o) == 1, (tag, subj)
        if n in s and o in n:
            continue
        s = s.replace(o, n)
        HITS.setdefault(subj, []).append(tag)
    return s


def msgfn(msg, subj):
    for tag, (o, n) in M.items():
        if o in msg and n not in msg:
            msg = msg.replace(o, n)
            HITS.setdefault(subj, []).append('msg' + tag)
    return msg


import atexit
import sys


@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-60s %s' % (k[:60], ' '.join(v)), file=sys.stderr)
