# a-1019 lreview r2 R6 (68160), applied by forktx5.py from 68160 up, on
# every branch that holds it:
#   R6  lfs.c: a --local/--fsname sweep asked a layout option (--pool,
#       --stripe-count, ...) failed ENOTSUP on every OST and exited non-zero,
#       though the MDT answers in full.  The sweep now skips the OSTs when it
#       holds an MDT and --ost was not given.  lfs-local copy of the
#       library's find_asks_layout(), no new export.  With no MDT, or with
#       --ost, each OST still fails as before; a named target is no sweep.
#   lfs-find.1 --local, conf-sanity test_300c and the commit message follow.
# Idempotent: every old text is gone, or kept as an anchor, after one pass.
HITS = {}
ANC = frozenset()

LFS = 'lustre/utils/lfs.c'
FIND1 = 'Documentation/man1/lfs-find.1'
CONF = 'lustre/tests/conf-sanity.sh'
CID_68160 = 'Ib25109943ad40afbc2d272a65e70c364c376b2b7'


def base(path):
    raise RuntimeError('set by the driver')


R = []      # (tag, path, old, new)

R.append(('helper', LFS,
'''/*
 * lfs find over a target's own objects, read off its device by
''',
'''/* the options only a layout answers, as find_asks_layout() in the library */
static bool lfs_find_asks_layout(const struct find_param *param)
{
	return param->fp_check_pool || param->fp_check_stripe_count ||
	       param->fp_check_stripe_size || param->fp_check_layout ||
	       param->fp_check_comp_count || param->fp_check_comp_end ||
	       param->fp_check_comp_start || param->fp_check_comp_flags ||
	       param->fp_check_mirror_count || param->fp_check_foreign ||
	       param->fp_check_mirror_state || param->fp_check_ext_size;
}

/*
 * lfs find over a target's own objects, read off its device by
'''))

R.append(('doc', LFS,
''' * A sweep skips the targets --ost or --mdt cannot name.  ENOTSUP does not
 * end it: an OST cannot answer everything an MDT can, and a node may serve
 * a kind of target this build has no backend for.
''',
''' * A sweep skips the targets --ost or --mdt cannot name, and the OSTs when
 * an MDT is there to answer the layout options.  ENOTSUP does not end it:
 * an OST cannot answer everything an MDT can, and a node may serve a kind
 * of target this build has no backend for.
'''))

R.append(('decl', LFS,
'''	int scanned = 0;
	int ret = 0;
	int named;
''',
'''	bool skip_ost = false;
	int scanned = 0;
	int ret = 0;
	int named;
'''))

R.append(('pre', LFS,
'''	for (i = 0; i < nr; i++) {
		int rc;

''',
'''	/* with no MDT, or with --ost, each OST says why it cannot answer */
	if (tgts != &one && param->fp_target == NULL &&
	    param->fp_obd_uuid == NULL && lfs_find_asks_layout(param)) {
		for (i = 0; i < nr; i++)
			skip_ost |= lfs_find_label_is(tgts[i].lt_name, "MDT");
	}

	for (i = 0; i < nr; i++) {
		int rc;

'''))

R.append(('loop', LFS,
'''			continue;
		scanned++;

		if (nr > 1)
''',
'''			continue;
		if (skip_ost && lfs_find_label_is(tgts[i].lt_name, "OST"))
			continue;
		scanned++;

		if (nr > 1)
'''))

R.append(('man', FIND1,
'''a sweep skips the targets of the other kind rather than failing on them,
and refuses the two options together, since no target would be left.
''',
'''a sweep skips the targets of the other kind rather than failing on them,
and refuses the two options together, since no target would be left.
Only an MDT answers the layout options, such as
.B --pool
and
.BR --stripe-count ,
so a sweep that reads an MDT skips the OSTs.
With no MDT to read, or with
.BR --ost ,
each OST fails as one that cannot answer them.
'''))

R.append(('test', CONF,
'''	if grep -q -- "-OST" $scan_err; then
		cat $scan_err
		error "lfs find --local --mdt $mdtsvc read an OST"
	fi
}
''',
'''	if grep -q -- "-OST" $scan_err; then
		cat $scan_err
		error "lfs find --local --mdt $mdtsvc read an OST"
	fi

	# only an MDT answers a layout option, so the sweep skips the OST
	do_facet mds1 "$LFS find --local --stripe-count 1 --type f" \\
		> $scan_out 2> $scan_err || {
		cat $scan_err
		error "lfs find --local --stripe-count 1 failed"
	}
	[[ -s $scan_out ]] ||
		error "lfs find --local --stripe-count 1 found nothing"
	if grep -q -- "-OST" $scan_err; then
		cat $scan_err
		error "lfs find --local --stripe-count 1 read an OST"
	fi
	# but an OST named alone still refuses it
	do_facet mds1 "$LFS find --target $ostsvc --stripe-count 1" \\
		> /dev/null 2>&1 &&
		error "lfs find --target $ostsvc --stripe-count 1 succeeded"
	return 0
}
'''))


def fn(path, s, subj):
    if s is None or CID_68160 not in ANC:
        return s
    for tag, p, o, n in R:
        if p != path or o not in s:
            continue
        # an insertion keeps its anchor: skip if already applied
        if o in n and n in s:
            continue
        assert s.count(o) == 1, (tag, subj, s.count(o))
        s = s.replace(o, n)
        HITS.setdefault(subj, []).append(tag)
    return s


M = {
    'M160a': (
        '''ENOTSUP does not end a sweep either: an OST cannot answer everything an
MDT can, and a node may serve a kind of target this build cannot read.
''',
        '''ENOTSUP does not end a sweep either: an OST cannot answer everything an
MDT can, and a node may serve a kind of target this build cannot read.
Only an MDT answers the layout options, so a sweep that reads an MDT
skips the OSTs: a node that serves an MDT and an OST answers --pool in
full and exits 0. With no MDT to read, or with --ost, each OST still
fails.
'''),
    'M160b': (
        '''ldiskfs node it also checks that each reads only targets of its type.
''',
        '''ldiskfs node it also checks that each reads only targets of its type,
that --local --stripe-count skips the OST and succeeds, and that
--target on the OST refuses it.
'''),
}


def msgfn(msg, subj):
    if CID_68160 not in msg:
        return msg
    for tag, (o, n) in M.items():
        if o in msg and n not in msg:
            msg = msg.replace(o, n)
            HITS.setdefault(subj, []).append('msg-' + tag)
    return msg


import atexit
import sys


@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-50s %s' % (k[:50], ' '.join(v)), file=sys.stderr)
