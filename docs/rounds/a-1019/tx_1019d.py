# a-1019 lreview fixes, applied by forktx5.py to every commit from 68156 up,
# on every branch (triage: a-1019/lreview/triage.md):
#   L1 68415 the library drops record types outside lfsc_type_mask
#   L4 68419 reflow three comment paragraphs
#   B1 68156 an old OST's IDIF with OST index 0 gets the target's index
#   B2 68156 llapi_scan_device.3: -EIO is wider, -ENOMEM added
#   B3 68156 fid_is_root() returns bool
#   C2 68159 llapi_find_device.3 example says what is not printed
#   D1 68160 name the expected target form
#   E1 68163 commit message: drop the two review-answer paragraphs
#   F1 68288 encrypted-directory limit covers --fid2path too
#   F2 68288 lfs refuses -printf with --paths/--fid2path once
# Idempotent: every old text is gone after one pass, and insertions check
# that their new text is not already there.
HITS = {}
ANC = frozenset()

C156 = 'I8a28a8173b0b8f03ba8f9dc5a58a821118ac6296'
C415 = 'I12efd3bd2150592a4507533129ab56573ef924d9'
C159 = 'Ibf2dcf71e5444914f306ad37a551262cddd8e1de'
C160 = 'Ib25109943ad40afbc2d272a65e70c364c376b2b7'
C163 = 'I97a6d8815924b2671c818152f42d66cc580a609d'
C288 = 'I6476abfd28c91b2ccc04fb08c4e5860aef8fe009'
C419 = 'Ia8ce93368a2c2c8c2ea2ee88c8e7f7e099b1bfa5'

SCL = 'lustre/utils/liblustreapi_scan_changelog.c'
SCL3 = 'Documentation/man3/llapi_scan_changelog.3'
SCLT = 'lustre/tests/llapi_scan_changelog_test.c'
SAN = 'lustre/tests/sanity.sh'
PF = 'lustre/utils/liblustreapi_pfind.c'
SD = 'lustre/utils/liblustreapi_scan_device.c'
SD3 = 'Documentation/man3/llapi_scan_device.3'
FIDH = 'include/uapi/linux/lustre/lustre_fid.h'
FD3 = 'Documentation/man3/llapi_find_device.3'
LFS = 'lustre/utils/lfs.c'
FIND1 = 'Documentation/man1/lfs-find.1'

ALWAYS = ()


def base(path):
    raise RuntimeError('set by the driver')


R = []      # (tag, path, old, new, gate) -- gate(ANC) -> bool, or None

# ---------------------------------------------------------------- L1
R.append(('L1-loop', SCL,
'''		if (scl.lfsc_endrec != 0 && rec->cr_index > scl.lfsc_endrec) {
			llapi_changelog_free(&rec);
			break;
		}

		sl->sl_stats.ss_seen++;
''',
'''		if (scl.lfsc_endrec != 0 && rec->cr_index > scl.lfsc_endrec) {
			llapi_changelog_free(&rec);
			break;
		}

		/* the mdc filters nothing if the user's mask misses this one */
		if (scl.lfsc_type_mask != 0 &&
		    (rec->cr_type >= 64 ||
		     !(scl.lfsc_type_mask & (1ULL << rec->cr_type)))) {
			llapi_changelog_free(&rec);
			continue;
		}

		sl->sl_stats.ss_seen++;
''', None))

R.append(('L1-man', SCL3,
'''of the events wanted, intersected with the registered user's own mask; 0
means every type the log holds. The client asks the MDS for
.IR lfsc_user 's
mask, which needs an MDS of Lustre 2.17.0 or later, and drops the other
records as it reads them; they are still read from the MDT. A mask is
refused without
.IR lfsc_user ,
because there is no user's mask to intersect it with, and refused with
.BR LLAPI_SCAN_CL_F_CLEAR ,
because a clear purges the user's records of every type, including the ones
the mask kept from the consumer. Keep the mask within the user's own: the
client takes an empty intersection as no mask at all, and delivers every
type.
.I lfsc_filter
filters without one.
''',
'''of the events wanted; 0 means every type the log holds. Only records of
these types are delivered. The client also asks the MDS for
.IR lfsc_user 's
mask, which needs an MDS of Lustre 2.17.0 or later, and where the two masks
overlap it drops the records outside the overlap as it reads them; they are
still read from the MDT. A mask is refused without
.IR lfsc_user ,
because there is no user's mask to intersect it with, and refused with
.BR LLAPI_SCAN_CL_F_CLEAR ,
because a clear purges the user's records of every type, including the ones
the mask kept from the consumer.
.I lfsc_filter
filters without a user.
''', None))

R.append(('L1-t-hdr', SCLT,
''' * without a mask (LU-20647).  Without -u, test6 and test9 skip.
''',
''' * without a mask (LU-20647).  Without -u, test6, test9 and test11 skip.
''', None))

R.append(('L1-t-case', SCLT,
'''static struct test_tbl_entry test_tbl[] = {
''',
'''#define T11_DESC "lfsc_type_mask holds outside the user's own mask"
static void test11(void)
{
	struct llapi_scan_changelog_param sc;
	struct cl_result res = { 0 };
	int rc;

	if (cluser == NULL) {
		printf("  no -u, so no user to filter for; skipped\\n");
		return;
	}

	ASSERTF(make_events(testdir) != 0, "cannot make events under %s",
		testdir);

	/*
	 * If this mask and the user's do not overlap, the mdc filters
	 * nothing.  sanity 56Eea runs this case with a user of CREAT only.
	 */
	param_init(&sc);
	sc.lfsc_type_mask = 1ULL << CL_UNLINK;
	rc = llapi_scan_changelog(&sc, cl_cb, &res);
	ASSERTF(rc == 0, "the masked scan failed: %s", strerror(-rc));
	ASSERTF(res.cr_types & (1ULL << CL_UNLINK),
		"the mask delivered no CL_UNLINK, though a file was unlinked");
	ASSERTF(!(res.cr_types & ~(1ULL << CL_UNLINK)),
		"the mask let other types through: %#llx",
		(unsigned long long)res.cr_types);

	printf("  %u records, all CL_UNLINK\\n", res.cr_with_event);
}

static struct test_tbl_entry test_tbl[] = {
''', None))

R.append(('L1-t-reg', SCLT,
'''	TEST_REGISTER(10),
	TEST_REGISTER_END
''',
'''	TEST_REGISTER(10),
	TEST_REGISTER(11),
	TEST_REGISTER_END
''', None))

R.append(('L1-san', SAN,
'''	llapi_scan_changelog_test -m $(facet_svc mds1) -d $MOUNT \\
		-u $cl_user ${skip_cases:+-e $skip_cases} ||
		error "llapi_scan_changelog_test failed"
}
run_test 56Eea "llapi changelog scanner API tests"
''',
'''	llapi_scan_changelog_test -m $(facet_svc mds1) -d $MOUNT \\
		-u $cl_user ${skip_cases:+-e $skip_cases} ||
		error "llapi_scan_changelog_test failed"

	# test11 again, with a user whose mask does not overlap the one it
	# asks for: the client then filters nothing, the library must
	(( MDS1_VERSION >= $(version_code 2.17.0) )) || return 0
	changelog_register -m creat ||
		error "changelog_register -m creat failed"
	cl_user=${CL_USERS[mds1]% }
	cl_user=${cl_user##* }
	llapi_scan_changelog_test -m $(facet_svc mds1) -d $MOUNT \\
		-u $cl_user -o 11 ||
		error "llapi_scan_changelog_test -o 11 failed"
}
run_test 56Eea "llapi changelog scanner API tests"
''', None))

# ---------------------------------------------------------------- L4
R.append(('L4-filter', PF,
''' * no object, such as a CL_MARK, is
 * delivered as it arrives -- scan_cl_object() routes it to scan_cl_event()
 * -- and an object already printed is dropped before the lookup too.
''',
''' * no object, such as a CL_MARK, is delivered as it arrives --
 * scan_cl_object() routes it to scan_cl_event() -- and an object already
 * printed is dropped before the lookup too.
''', lambda a: C419 in a))

R.append(('L4-next', PF,
''' * names.  What happens next depends on
 * the source.
''',
''' * names.  What happens next depends on the source.
''', lambda a: C419 in a))

R.append(('L4-return', PF,
''' * one of them) and --changelog names none, if the cookie is not a regular
 * file or was written for
 * another filesystem or another search root, if --resolve is given without
 * --changelog, or if @path is below the mount under --changelog without
 * --resolve.  -ENODEV for a --changelog MDT name that names no MDT of this
 * filesystem.  -ENOTSUP for a predicate the source cannot answer, which
 * find_changelog_supported() lists.  -ESTALE for a cookie whose anchor the
 * log has already passed.
''',
''' * one of them) and --changelog names none, if the cookie is not a regular
 * file or was written for another filesystem or another search root, if
 * --resolve is given without --changelog, or if @path is below the mount
 * under --changelog without --resolve.  -ENODEV for a --changelog MDT name
 * that names no MDT of this filesystem.  -ENOTSUP for a predicate the source
 * cannot answer, which find_changelog_supported() lists.  -ESTALE for a
 * cookie whose anchor the log has already passed.
''', lambda a: C419 in a))

# ---------------------------------------------------------------- B1
R.append(('B1-helper', SD,
'''	return (dev->sd_tgt_info.tt_flags & need) == need &&
	       dev->sd_tgt_info.tt_index == 0;
}
''',
'''	return (dev->sd_tgt_info.tt_flags & need) == need &&
	       dev->sd_tgt_info.tt_index == 0;
}

/*
 * An OST without OBD_ROCOMPAT_IDX_IN_IDIF (formatted before 2.6) stores its
 * IDIFs with OST index 0.  osd_check_lma() puts the index back, and so here.
 */
static void scan_idif_set_index(const struct scan_dev *dev, struct lu_fid *fid)
{
	__u32 need = LLAPI_SCAN_TGT_OST | LLAPI_SCAN_TGT_INDEX;
	__u32 idx = dev->sd_tgt_info.tt_index;

	if ((dev->sd_tgt_info.tt_flags & need) != need || idx == 0 ||
	    idx > 0xffff || !fid_is_idif(fid) || fid_idif_ost_idx(fid) != 0)
		return;

	fid->f_seq = fid_idif_seq(fid_idif_id(fid->f_seq, fid->f_oid,
					      fid->f_ver), idx);
}
''', None))

R.append(('B1-call', SD,
'''		rec.lfsr_fid = lma.lma_self_fid;
		if (fid_is_sane(&rec.lfsr_fid))
''',
'''		rec.lfsr_fid = lma.lma_self_fid;
		scan_idif_set_index(dev, &rec.lfsr_fid);
		if (fid_is_sane(&rec.lfsr_fid))
''', None))

R.append(('B1-man', SD3,
'''or an IDIF sequence), one stripe of some file's data.
''',
'''or an IDIF sequence), one stripe of some file's data. An OST formatted
before Lustre 2.6 stores its IDIFs with OST index 0;
.I lfsr_fid
carries the index from the target's label instead, as the OSD does.
''', None))

# ---------------------------------------------------------------- B2
R.append(('B2-eio156', SD3,
'''.B -EIO
a read of the target's inode table failed. An object that cannot be read
is skipped and counted in
''',
'''.B -EIO
a read the scan cannot go on without failed: the superblock, the group
descriptors, the inode bitmap or the inode table. An object that cannot be
read is skipped and counted in
''', None))

R.append(('B2-eio163', SD3,
'''.B -EIO
a read the scan cannot go on without failed: the inode table on
ldiskfs, the attribute registry or a dnode block on ZFS. An object that
cannot be read is skipped and counted in
''',
'''.B -EIO
a read the scan cannot go on without failed: the superblock, the group
descriptors, the inode bitmap or the inode table on ldiskfs, the attribute
registry or a dnode block on ZFS. An object that cannot be read is skipped
and counted in
''', None))

R.append(('B2-enomem', SD3,
'''.SH NOTES
With
.I lfsp_thread_count
''',
'''.TP 15
.B -ENOMEM
out of memory.
.SH NOTES
With
.I lfsp_thread_count
''', None))

# ---------------------------------------------------------------- B3
R.append(('B3', FIDH,
'''static inline int fid_is_root(const struct lu_fid *fid)
''',
'''static inline bool fid_is_root(const struct lu_fid *fid)
''', None))

# ---------------------------------------------------------------- C2
R.append(('C2', FD3,
'''To print every regular file over a gigabyte on a stopped MDT, without
mounting it:
''',
'''To print the regular files over a gigabyte on a stopped MDT, without
mounting it. A file whose size the MDT does not hold, such as a striped
file with no
.BR trusted.som ,
is counted as undecided and not printed:
''', None))

# ---------------------------------------------------------------- D1
R.append(('D1', LFS,
'''		fprintf(stderr, "%s: '%s' is not an MDT or an OST\\n",
			argv[0], param->fp_target);
''',
'''		fprintf(stderr,
			"%s: '%s' is not a target name like FSNAME-MDT0000 or FSNAME-OST0000\\n",
			argv[0], param->fp_target);
''', None))

# ---------------------------------------------------------------- F1
R.append(('F1-find1', FIND1,
'''.B --paths
does not name an object below an encrypted directory either:
the target holds those names encrypted.
''',
'''On an MDT, neither option names an object below an encrypted directory:
the target holds those names encrypted.
''', None))

R.append(('F1-fd3', FD3,
'''.BR .lustre ,
and under DNE anything whose ancestors live on another MDT. Such an object
''',
'''.BR .lustre ,
anything below an encrypted directory, whose names the target holds
encrypted, and under DNE anything whose ancestors live on another MDT.
Such an object
''', None))

# 69729 rewrote the sentence: .lustre now has a name
R.append(('F1-fd3-729', FD3,
'''build: under DNE, anything whose ancestors live on another MDT. Such an
''',
'''build: anything below an encrypted directory, whose names the target holds
encrypted, and under DNE, anything whose ancestors live on another MDT.
Such an
''', None))

# ---------------------------------------------------------------- F2
R.append(('F2', LFS,
'''	if (param->fp_xattr_match_info != NULL) {
		fprintf(stderr, "%s: --xattr needs a mounted filesystem\\n",
			argv[0]);
		return -ENOTSUP;
	}
''',
'''	if (param->fp_xattr_match_info != NULL) {
		fprintf(stderr, "%s: --xattr needs a mounted filesystem\\n",
			argv[0]);
		return -ENOTSUP;
	}
	/* -printf prints its own fields, never the composed pathname */
	if (param->fp_format_printf_str != NULL &&
	    (param->fp_paths || param->fp_fid2path_mnt != NULL)) {
		fprintf(stderr,
			"%s: -printf cannot be used with --paths or --fid2path\\n",
			argv[0]);
		return -ENOTSUP;
	}
''', lambda a: C288 in a))


def gate_ok(gate):
    return gate is None or gate(ANC)


def fn(path, s, subj):
    if s is None:
        return s
    for tag, p, o, n, gate in R:
        if p != path or o not in s or not gate_ok(gate):
            continue
        assert s.count(o) == 1, (tag, subj, s.count(o))
        if n in s and o in n:
            continue        # an insertion keeps its anchor: done already
        s = s.replace(o, n)
        HITS.setdefault(subj, []).append(tag)
    return s


# ---------------------------------------------------------------- messages
M = {
    'L1': (
        '''- lfsc_type_mask selects event types and needs lfsc_user. The client
  drops the other records as it reads them.
''',
        '''- lfsc_type_mask selects event types and needs lfsc_user. The client
  drops the other records as it reads them, but only where this mask and
  the user's own overlap, so the library drops them too.
'''),
    'B1': (
        '''- LLAPI_SCAN_PARENT is set only when the parent FID is sane.
''',
        '''- LLAPI_SCAN_PARENT is set only when the parent FID is sane.
- An OST formatted before 2.6 stores its IDIFs with OST index 0. The
  index from the label is put back, as osd_check_lma() does.
'''),
    'E1': (
        '''Its own autotest reaches the ZFS half only where configure finds the
headers; the Test-Parameters line below asks for the ZFS session that
can say something, and the default testing already runs sanity 157c.

Neither exercises the weak slot, and that is not an omission.
PLUGINS is enable_shared, so the weak references, libscan_zfs_in.la
and the -u exist only in a --disable-shared build; the autotest
sessions are built from the spec, which is %bcond_without shared, and
take the dlopen() path.  The build that does carry them is the
janitor's, which configures --disable-shared and runs the whole of
sanity on every change.
Asking for ONLY=131d here would run it against the shared build,
where the condition cannot arise.

''',
        ''''''),
    'F2': (
        '''Refused: --paths with --fid2path, --paths on an OST, either option
without a target, and -printf with either option, because a format
prints its own fields and not the pathname.
''',
        '''Refused: --paths with --fid2path, --paths on an OST, either option
without a target, and -printf with either option, because a format
prints its own fields and not the pathname. lfs refuses -printf with
either option once, not once for each target of a sweep.
'''),
}


def msgfn(msg, subj):
    for tag, (o, n) in M.items():
        if o in msg and (n == '' or n not in msg):
            msg = msg.replace(o, n)
            HITS.setdefault(subj, []).append('msg-' + tag)
    return msg


import atexit
import sys


@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-50s %s' % (k[:50], ' '.join(v)), file=sys.stderr)
