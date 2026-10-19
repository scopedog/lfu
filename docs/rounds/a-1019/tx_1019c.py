# a-1019 adilger on 68156 (2026-10-19 21:03 UTC), applied by forktx5.py to
# every commit from 68156 up, on every branch:
#   A1 commit message: no patch history ("with fixes")
#   A2 %LF on an OST data object is its file's MDT FID; new %LO prints OST
#      object FIDs (68159), the owner arrives with 68288
#   A3 conf-sanity 300a/300b and llapi_scan_device_test move from 68156 to
#      68160, which adds lfs find --device; the -l FID list is replaced by
#      lfs find --device -printf %LF
#   A4 -printf %LF on both sides (already so at 68160, where the test lives)
#   A5 libscan_ldiskfs.c label comment no longer overstates
# Idempotent: every old text is gone after one pass, and insertions check
# that their new text is not already there.
HITS = {}
ANC = frozenset()

C156 = 'I8a28a8173b0b8f03ba8f9dc5a58a821118ac6296'
C159 = 'Ibf2dcf71e5444914f306ad37a551262cddd8e1de'
C160 = 'Ib25109943ad40afbc2d272a65e70c364c376b2b7'
C163 = 'I97a6d8815924b2671c818152f42d66cc580a609d'
C288 = 'I6476abfd28c91b2ccc04fb08c4e5860aef8fe009'

PF = 'lustre/utils/liblustreapi_pfind.c'
LAY = 'lustre/utils/liblustreapi_layout.c'
IH = 'lustre/utils/lustreapi_internal.h'
LDK = 'lustre/utils/libscan_ldiskfs.c'
CS = 'lustre/tests/conf-sanity.sh'
SAN = 'lustre/tests/sanity.sh'
TOOL = 'lustre/tests/llapi_scan_device_test.c'
TMK = 'lustre/tests/Makefile.am'
TGI = 'lustre/tests/.gitignore'
TU = ('lustre/tests/llapi_test_utils.c', 'lustre/tests/llapi_test_utils.h')
FIND1 = 'Documentation/man1/lfs-find.1'
FD3 = 'Documentation/man3/llapi_find_device.3'

# files a commit may not change against master but that a transform reads
ALWAYS = (FIND1, SAN)


def base(path):
    raise RuntimeError('set by the driver')


# ---------------------------------------------------------------- A5
R = []      # (tag, path, old, new, gate) -- gate(ANC) -> bool, or None

R.append(('A5', LDK,
'''/*
 * A target's label is what mkfs.lustre wrote there: fsname-MDT0000.  It is
 * free at open time and it is the only thing on the device that says which
 * target this is, so it settles both the index and MDT versus OST.
 */''',
'''/*
 * The label mkfs.lustre wrote, fsname-MDT0000, gives the index and MDT versus
 * OST.  last_rcvd and CONFIGS/mountdata name the target too, and the mount
 * checks them against it, but the label is free at open time.
 */''', None))

# ---------------------------------------------------------------- A2 code
R.append(('A2-letters', PF,
'''	if (*seq == '\\0' || strchr("aAFPchiopS", *seq) == NULL) {''',
'''	if (*seq == '\\0' || strchr("aAFOPchiopS", *seq) == NULL) {''', lambda a: C159 in a))

R.append(('A2-F', PF,
'''			 * default output of such a scan reads it from too,
			 * and an object carrying no trusted.lma has none.
			 */
			if (rec != NULL && (rec->lfsr_valid & LLAPI_SCAN_FID))
				*wrote = snprintf(buffer, size, DFID_NOBRACE,
						  PFID(&rec->lfsr_fid));
			goto format_done;''',
'''			 * default output of such a scan reads it from too,
			 * and an object carrying no trusted.lma has none.
			 * An OST data object prints nothing: the FID a user
			 * knows is its file's, which is not read here.
			 */
			if (rec == NULL || find_rec_is_ost_obj(rec) ||
			    !(rec->lfsr_valid & LLAPI_SCAN_FID))
				goto format_done;
			*wrote = snprintf(buffer, size, DFID_NOBRACE,
					  PFID(&rec->lfsr_fid));
			goto format_done;''', lambda a: C159 in a))

# 68288 reads the owner: %LF on an OST data object prints it
R.append(('A2-F288', PF,
'''			 * An OST data object prints nothing: the FID a user
			 * knows is its file's, which is not read here.
			 */
			if (rec == NULL || find_rec_is_ost_obj(rec) ||
			    !(rec->lfsr_valid & LLAPI_SCAN_FID))
				goto format_done;
			*wrote = snprintf(buffer, size, DFID_NOBRACE,
					  PFID(&rec->lfsr_fid));
			goto format_done;''',
'''			 * An OST data object prints its file's FID, from its
			 * trusted.fid, and nothing if no file owns it yet.
			 */
			if (rec == NULL)
				goto format_done;
			if (!find_rec_is_ost_obj(rec) &&
			    (rec->lfsr_valid & LLAPI_SCAN_FID))
				fid = rec->lfsr_fid;
			else if (find_rec_is_ost_obj(rec) &&
				 (rec->lfsr_valid & LLAPI_SCAN_OWNER))
				fid = rec->lfsr_owner_fid;
			else
				goto format_done;
			*wrote = snprintf(buffer, size, DFID_NOBRACE,
					  PFID(&fid));
			goto format_done;''', lambda a: C288 in a))

R.append(('A2-O', PF,
'''	case 'P':
		*wrote = snprintf(buffer, size, "%u", projid);
		goto format_done;''',
'''	case 'O':
		/* an OST data object is one of its file's: only its own FID */
		if (rec != NULL && find_rec_is_ost_obj(rec)) {
			if (rec->lfsr_valid & LLAPI_SCAN_FID)
				*wrote = snprintf(buffer, size,
						  "[" DFID_NOBRACE "]",
						  PFID(&rec->lfsr_fid));
			goto format_done;
		}
		break;
	case 'P':
		*wrote = snprintf(buffer, size, "%u", projid);
		goto format_done;''', lambda a: C159 in a))

R.append(('A2-Ofile', PF,
'''		case 'o':	/* list of object indices */
			*wrote = printf_format_ost_indices(buffer, size, layout,
							   path == NULL);
			break;''',
'''		case 'o':	/* list of object indices */
			*wrote = printf_format_ost_indices(buffer, size, layout,
							   path == NULL);
			break;
		case 'O':	/* list of object FIDs */
			*wrote = printf_format_ost_fids(buffer, size, layout);
			break;''', lambda a: C159 in a))

R.append(('A2-Odir', PF,
'''		case 'p':	/* pool name */
			*wrote = snprintf(buffer, size, "%s",''',
'''		case 'O':	/* a directory has no OST objects */
			break;
		case 'p':	/* pool name */
			*wrote = snprintf(buffer, size, "%s",''', lambda a: C159 in a))

R.append(('A2-helpers', PF,
'''/*
 * Print all ost indices associated with a file layout using a commma separated
 * list.''',
'''/* An OST data object: one stripe of a file, which the file names */
static bool find_rec_is_ost_obj(const struct llapi_scan_rec *rec)
{
	return (rec->lfsr_valid & LLAPI_SCAN_CLASS) &&
	       rec->lfsr_class == LLAPI_SCAN_CLS_OST_OBJ;
}

/*
 * The FIDs of a file's OST objects, comma-separated, with one bracketed list
 * per component as %Lo prints the indices.  A stripe with no object yet is
 * left out, and a component with none prints nothing.
 */
static int printf_format_ost_fids(char *buffer, size_t size,
				  struct llapi_layout *layout)
{
	size_t wrote = 0;
	int rc;

	rc = llapi_layout_comp_use(layout, LLAPI_LAYOUT_COMP_USE_FIRST);
	while (rc == 0) {
		uint64_t count, i;
		bool listed = false;

		if (llapi_layout_stripe_count_get(layout, &count) != 0 ||
		    count >= LLAPI_LAYOUT_INVALID)
			count = 0;
		for (i = 0; i < count && wrote < size; i++) {
			struct lu_fid fid;

			if (layout_ost_fid_get(layout, i, &fid) != 0)
				continue;
			wrote += snprintf(buffer + wrote, size - wrote,
					  "%c" DFID_NOBRACE, listed ? ',' : '[',
					  PFID(&fid));
			listed = true;
		}
		if (listed && wrote < size)
			wrote += snprintf(buffer + wrote, size - wrote, "]");
		rc = llapi_layout_comp_use(layout, LLAPI_LAYOUT_COMP_USE_NEXT);
	}

	return wrote < size ? wrote : size - 1;
}

/*
 * Print all ost indices associated with a file layout using a commma separated
 * list.''', lambda a: C159 in a))

R.append(('A2-want', PF,
'''			if (c[1] != '\\0' && strchr("chiopS", c[1]) != NULL)
				want |= LLAPI_SCAN_LAYOUT | LLAPI_SCAN_LMV;''',
'''			if (c[1] != '\\0' && strchr("chiOopS", c[1]) != NULL)
				want |= LLAPI_SCAN_LAYOUT | LLAPI_SCAN_LMV;''', lambda a: C159 in a))

R.append(('A2-want288', PF,
'''			if (c[1] != '\\0' && strchr("chiOopS", c[1]) != NULL)
				want |= LLAPI_SCAN_LAYOUT | LLAPI_SCAN_LMV;''',
'''			if (c[1] != '\\0' && strchr("chiOopS", c[1]) != NULL)
				want |= LLAPI_SCAN_LAYOUT | LLAPI_SCAN_LMV;
			/* an OST data object's %LF is its owner's */
			if (c[1] == 'F')
				want |= LLAPI_SCAN_OWNER;''', lambda a: C288 in a))

R.append(('A2-layout', LAY,
'''	if (comp->llc_stripe_offset == LLAPI_LAYOUT_DEFAULT)
		*index = LLAPI_LAYOUT_DEFAULT;
	else
		*index = comp->llc_objects[stripe_number].l_ost_idx;

	return 0;
}
''',
'''	if (comp->llc_stripe_offset == LLAPI_LAYOUT_DEFAULT)
		*index = LLAPI_LAYOUT_DEFAULT;
	else
		*index = comp->llc_objects[stripe_number].l_ost_idx;

	return 0;
}

/*
 * The FID of the object @stripe_number in the current component, for
 * lfs find -printf %LO.  -ENODATA for a stripe with no object yet.
 */
int layout_ost_fid_get(const struct llapi_layout *layout,
		       uint64_t stripe_number, struct lu_fid *fid)
{
	struct llapi_layout_comp *comp;
	struct lov_user_ost_data_v1 *obj;

	comp = __llapi_layout_cur_comp(layout);
	if (comp == NULL)
		return -EINVAL;
	if (comp->llc_pattern == LLAPI_LAYOUT_FOREIGN ||
	    stripe_number >= comp->llc_stripe_count ||
	    stripe_number >= comp->llc_objects_count)
		return -EINVAL;

	obj = &comp->llc_objects[stripe_number];
	if (ostid_id(&obj->l_ost_oi) == 0)
		return -ENODATA;

	return ostid_to_fid(fid, &obj->l_ost_oi, obj->l_ost_idx);
}
''', lambda a: C159 in a))

R.append(('A2-decl', IH,
'''void layout_swab_lov_user_md(struct lov_user_md *lum, int lum_size);
''',
'''void layout_swab_lov_user_md(struct lov_user_md *lum, int lum_size);
int layout_ost_fid_get(const struct llapi_layout *layout,
		       uint64_t stripe_number, struct lu_fid *fid);
''', lambda a: C159 in a))

# ---------------------------------------------------------------- A2 tests
R.append(('A2-56Ea', SAN,
'''	[[ "${lattr_printf}" == "${lattr_getstr}" ]] ||
		error "Attrs from lfs find and lfs getstripe don't match"
''',
'''	[[ "${lattr_printf}" == "${lattr_getstr}" ]] ||
		error "Attrs from lfs find and lfs getstripe don't match"

	# %LO lists the OST object FIDs lfs getstripe -y gives, and a
	# directory has none
	local ofids=$($LFS getstripe -y $path/$tfile |
		      awk '/l_fid:/ { printf "%s%s", s, $2; s = "," }')
	local lo_printf=$($LFS find $path/$tfile -printf "%LO")

	[[ -n "$ofids" && "$lo_printf" == "[$ofids]" ]] ||
		error "%LO gave '$lo_printf', getstripe gives [$ofids]"
	lo_printf=$($LFS find $path -maxdepth 0 -printf "%LO")
	[[ -z "$lo_printf" ]] || error "%LO gave '$lo_printf' for a directory"
''', lambda a: C159 in a))

# ---------------------------------------------------------------- A2 man
R.append(('A2-find1', FIND1,
'''.TP
.B %Lo
List of all OST/MDT indices associated with a file or directory.
''',
'''.TP
.B %Lo
List of all OST/MDT indices associated with a file or directory.
.TP
.B %LO
List of the FIDs of a file's OST objects, comma-separated, with one list in
brackets for each layout component, as
.B %Lo
lists the indices. A directory has none.
''', lambda a: C159 in a))

R.append(('A2-find1-160', FIND1,
'''A target holds no pathnames, so each match is printed as its FID.
''',
'''A target holds no pathnames, so each match is printed as its FID.
On an OST that is the data object's own FID, which
.B -printf %LO
prints too;
.B %LF
prints nothing for a data object.
''', None))

R.append(('A2-find1-288', FIND1,
'''.B --paths
is given.
.SH NOTES''',
'''.B --paths
is given.
On an OST that is the data object's own FID, which
.B -printf %LO
prints too;
.B %LF
prints the FID of the file the object belongs to.
.SH NOTES''', None))

R.append(('A2-fd3', FD3,
'''.B %LF
prints the FID the record carries, and nothing for an object the scan has no
FID for;
''',
'''.B %LF
prints the FID the record carries, and nothing for an object the scan has no
FID for, or for an OST data object: the FID a user knows for one is its
file's, which this scan does not read.
.B %LO
prints an OST data object's own FID, in brackets, and the FIDs of a file's OST
objects from its layout;
''', lambda a: C159 in a))

R.append(('A2-fd3-288', FD3,
'''FID for, or for an OST data object: the FID a user knows for one is its
file's, which this scan does not read.
''',
'''FID for.
For an OST data object it prints the FID of the file the object belongs to,
from its
.BR trusted.fid ,
and nothing for one no file owns yet.
''', lambda a: C288 in a))

# ---------------------------------------------------------------- A3 tool
R.append(('A3-tool-hdr', TOOL,
''' * not the scanner's.  conf-sanity 300 runs this after stopall and so never
 * meets it.
 *
 * With -l it prints one FID per object instead, which is what makes the
 * conf-sanity oracle possible.
 *
''',
''' * not the scanner's.  conf-sanity 300 runs this after stopall and so never
 * meets it.
 *
''', None))

R.append(('A3-tool-list160', TOOL,
'''/* One FID per line, for a caller diffing this against what a client sees. */
static int fid_cb(const struct llapi_scan_rec *rec, void *data)
{
	if (rec->lfsr_valid & LLAPI_SCAN_FID)
		printf(DFID"\\n", PFID(&rec->lfsr_fid));
	return 0;
}

static int list_fids(void)
{
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp) };
	int rc;

	rc = llapi_scan_device(device, &sp, fid_cb, NULL);
	if (rc < 0)
		fprintf(stderr, "%s: %s\\n", device, strerror(-rc));

	return rc == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}

''', '', None))

R.append(('A3-tool-list163', TOOL,
'''/* One FID per line, for a caller diffing this against what a client sees. */
static int fid_cb(const struct llapi_scan_rec *rec, void *data)
{
	if (rec->lfsr_valid & LLAPI_SCAN_FID)
		printf(DFID"\\n", PFID(&rec->lfsr_fid));
	return 0;
}

static int list_fids(void)
{
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp),
				       .lfsp_search = search };
	int rc;

	rc = llapi_scan_device(device, &sp, fid_cb, NULL);
	if (rc < 0)
		fprintf(stderr, "%s: %s\\n", device, strerror(-rc));

	return rc == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}

''', '', None))

R.append(('A3-tool-usage160', TOOL,
'''		"Usage: %s [-l] [-e <test>] [-o <test>] -d <device>\\n"
		"       -d  the target to scan, read-only\\n"
		"       -l  list the FID of every object, one per line\\n"
''',
'''		"Usage: %s [-e <test>] [-o <test>] -d <device>\\n"
		"       -d  the target to scan, read-only\\n"
''', None))

R.append(('A3-tool-usage163', TOOL,
'''		"Usage: %s [-l] [-e <test>] [-o <test>] [-p <dirs>] -d <device>\\n"
		"       -d  the target to scan, read-only\\n"
		"       -l  list the FID of every object, one per line\\n"
''',
'''		"Usage: %s [-e <test>] [-o <test>] [-p <dirs>] -d <device>\\n"
		"       -d  the target to scan, read-only\\n"
''', None))

R.append(('A3-tool-main1', TOOL,
'''	bool list = false;
	int c;
''',
'''	int c;
''', None))
R.append(('A3-tool-getopt160', TOOL, '"d:e:lo:")', '"d:e:o:")', None))
R.append(('A3-tool-getopt163', TOOL, '"d:e:lo:p:")', '"d:e:o:p:")', None))
R.append(('A3-tool-main2', TOOL,
'''		case 'l':
			list = true;
			break;
''', '', None))
R.append(('A3-tool-main3', TOOL,
'''	if (list)
		return list_fids();

''', '', None))

R.append(('A3-mk163', TMK,
'''# conf-sanity 300 drives this as the oracle for a ZFS target, so it needs the
# ZFS backend, which liblustreapi does not link.''',
'''# conf-sanity 300 runs this against a ZFS target, so it needs the ZFS
# backend, which liblustreapi does not link.''', None))

# before 68160 the tool is not there: Makefile.am and .gitignore lose it
PRE160 = lambda a: C160 not in a
R.append(('A3-mk-pre', TMK,
'''THETESTS += llapi_scan_test llapi_scan_device_test
''',
'''THETESTS += llapi_scan_test
''', PRE160))
R.append(('A3-mk-pre2', TMK,
'''llapi_scan_device_test_SOURCES = llapi_scan_device_test.c llapi_test_utils.c \\
				 llapi_test_utils.h
llapi_scan_device_test_LDADD = $(LIBLUSTREAPI) -lpthread
''', '', PRE160))
R.append(('A3-gi-pre', TGI, '''/llapi_scan_device_test
''', '', PRE160))

# ---------------------------------------------------------------- A3 300a
R.append(('A3-300a-locals', CS,
'''	local file_fids=$TMP/$tfile.files
	local find_fids=$TMP/$tfile.find
	local missing
''',
'''	local file_fids=$TMP/$tfile.files
	local find_fids=$TMP/$tfile.find
	local lo_fids=$TMP/$tfile.lo
	local missing
''', None))

R.append(('A3-300a-striped', CS,
'''	createmany -o $DIR/$tdir/$tfile- 100 || error "createmany failed"
	test_mkdir -c 1 -i 0 $DIR/$tdir/subdir || error "mkdir subdir failed"
''',
'''	createmany -o $DIR/$tdir/$tfile- 100 || error "createmany failed"
	test_mkdir -c 1 -i 0 $DIR/$tdir/subdir || error "mkdir subdir failed"
	# over every OST, so that %LO has more than one FID to list
	$LFS setstripe -c -1 $DIR/$tdir/striped || error "setstripe failed"
''', None))

R.append(('A3-300a-loclient', CS,
r'''	$LFS find $DIR/$tdir -type f -printf "%LF\n" | sort > $file_fids
	[[ -s $file_fids ]] || error "no regular files from the client"
''',
r'''	$LFS find $DIR/$tdir -type f -printf "%LF\n" | sort > $file_fids
	[[ -s $file_fids ]] || error "no regular files from the client"

	# and each file's OST object FIDs, which the MDT has in its layout;
	# the striped file's are checked against lfs getstripe
	$LFS find $DIR/$tdir -type f -printf "%LF %LO\n" | sort > $lo_fids
	local ofids=$($LFS getstripe -y $DIR/$tdir/striped |
		      awk '/l_fid:/ { printf "%s%s", s, $2; s = "," }')

	grep -qxF -- "$($LFS path2fid $DIR/$tdir/striped | tr -d '[]') \
[$ofids]" $lo_fids || error "%LO of striped is not [$ofids]"
''', None))

# the -l list becomes lfs find --device -printf %LF (both forms)
R.append(('A3-300a-l160', CS,
r'''	do_facet mds1 "$scanner -d $mdt1 -l" > $scan_fids.raw 2> $scan_err || {
		cat $scan_err
		error "scanning $mdt1 failed"
	}
	tr -d '[]' < $scan_fids.raw | sort > $scan_fids
''',
r'''	do_facet mds1 "$LFS find --device $mdt1 -printf '%LF\n'" \
		> $scan_fids.raw 2> $scan_err || {
		cat $scan_err
		error "lfs find --device $mdt1 failed"
	}
	sort $scan_fids.raw > $scan_fids
''', None))

R.append(('A3-300a-l163', CS,
r'''	do_facet mds1 "$scanner -d $mdt1 ${sdir:+-p $sdir} -l" \
		> $scan_fids.raw 2> $scan_err || {
		[[ "$mds1_FSTYPE" == zfs ]] && zfs_scan_unbuilt $scan_err &&
			skip "no zfs scan backend in this build"
		cat $scan_err
		error "scanning $mdt1 failed"
	}
	tr -d '[]' < $scan_fids.raw | sort > $scan_fids
''',
r'''	do_facet mds1 "$LFS find --device $mdt1 ${sdir:+--search $sdir} \
			-printf '%LF\n'" > $scan_fids.raw 2> $scan_err || {
		[[ "$mds1_FSTYPE" == zfs ]] && zfs_scan_unbuilt $scan_err &&
			skip "lfs has no zfs scan backend in this build"
		cat $scan_err
		error "lfs find --device $mdt1 failed"
	}
	sort $scan_fids.raw > $scan_fids
''', None))


def lo_dev(zfs):
    search = ' ${sdir:+--search $sdir}' if zfs else ''
    return r'''	echo "lfs find --type f found all $(wc -l < $file_fids) files"

	# %LO read off the MDT gives each file the FIDs the client saw
	do_facet mds1 "$LFS find --device $mdt1@SEARCH@ \
			--type f -printf '%LF %LO\n'" > $lo_fids.raw ||
		error "lfs find -printf %LO on $mdt1 failed"
	sort $lo_fids.raw > $lo_fids.dev
	missing=$(comm -23 $lo_fids $lo_fids.dev)
	[[ -z "$missing" ]] || {
		echo "$missing" | head -20
		error "%LO differs for $(echo "$missing" | wc -l) files"
	}
'''.replace('@SEARCH@', search)


R_FN = []   # (tag, path, old, fn(s) -> new, gate)
R_FN.append(('A3-300a-lodev', CS,
r'''	echo "lfs find --type f found all $(wc -l < $file_fids) files"
''', lambda s: lo_dev('zfs_scan_unbuilt' in s), None))

# ---------------------------------------------------------------- A3 300b


def b_fmt():
    return '%LF %LO' if C288 in ANC else '%LO'


def b_setup(s):
    return r'''	check_mount || error "check_mount failed"
	# on ost1 alone, and written: a write gives each object the
	# trusted.fid that names its file, which a precreated one lacks
	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $tdir failed"
	$LFS setstripe -i 0 -c 1 $DIR/$tdir || error "setstripe $tdir failed"
	for ((i = 0; i < 20; i++)); do
		echo $i > $DIR/$tdir/$tfile-$i || error "write $tfile-$i failed"
	done
	# what the scan of ost1 has to give back for each of them
	$LFS find $DIR/$tdir -type f -printf "%s\n" | sort > $want
	[[ -s $want ]] || error "no OST object FIDs from the client"
	# a client sync does not commit the OST
	sync
	do_facet ost1 "sync; sync"
	stopall
	stack_trap setupall
''' % b_fmt()


R_FN.append(('A3-300b-setup', CS,
'''	check_mount || error "check_mount failed"
	createmany -o $DIR/$tfile- 100 || error "createmany failed"
	stopall
	stack_trap setupall
''', b_setup, None))

R.append(('A3-300b-loc160', CS,
'''	local scanner=${SCANNER:-$LUSTRE/tests/llapi_scan_device_test}

	is_mounted $MOUNT || setup_noconfig
''',
'''	local scanner=${SCANNER:-$LUSTRE/tests/llapi_scan_device_test}
	local scan_err=$TMP/$tfile.scanerr
	local want=$TMP/$tfile.want
	local missing

	stack_trap "rm -f $TMP/$tfile.*"

	is_mounted $MOUNT || setup_noconfig
''', None))

R.append(('A3-300b-loc163', CS,
'''	local scan_err=$TMP/$tfile.scanerr

	stack_trap "rm -f $TMP/$tfile.*"

	is_mounted $MOUNT || setup_noconfig
''',
'''	local scan_err=$TMP/$tfile.scanerr
	local want=$TMP/$tfile.want
	local missing

	stack_trap "rm -f $TMP/$tfile.*"

	is_mounted $MOUNT || setup_noconfig
''', None))


def b_check(zfs):
    if C288 in ANC:
        what = ('# lfs find over the same OST: %LF is each object\'s file, '
                'read from\n\t# its trusted.fid, and %LO the object itself')
    else:
        what = '# lfs find over the same OST: %LO is each object\'s own FID'
    search = ' ${odir:+--search $odir}' if zfs else ''
    skip = ('''		[[ "$ost1_FSTYPE" == zfs ]] && zfs_scan_unbuilt $scan_err &&
			skip "lfs has no zfs scan backend in this build"
''' if zfs else '')
    return r'''
	%s
	do_facet ost1 "$LFS find --device $(ostdevname 1)%s \
			-printf '%s\n'" > $want.raw 2> $scan_err || {
%s		cat $scan_err
		error "lfs find --device $(ostdevname 1) failed"
	}
	sort $want.raw > $want.dev
	missing=$(comm -23 $want $want.dev)
	[[ -z "$missing" ]] || {
		echo "$missing" | head -20
		error "$(echo "$missing" | wc -l) objects not given back"
	}
}
run_test 300b "llapi_scan_device reads an OST's data objects"
''' % (what, search, b_fmt(), skip)


R_FN.append(('A3-300b-check160', CS,
'''		error "llapi_scan_device_test on $(ostdevname 1) failed"
}
run_test 300b "llapi_scan_device reads an OST's data objects"
''', lambda s: '''		error "llapi_scan_device_test on $(ostdevname 1) failed"
''' + b_check(False), None))

R_FN.append(('A3-300b-check163', CS,
'''		error "scanning $(ostdevname 1) failed"
	}
}
run_test 300b "llapi_scan_device reads an OST's data objects"
''', lambda s: '''		error "scanning $(ostdevname 1) failed"
	}
''' + b_check(True), None))


def gate_ok(gate):
    return gate is None or gate(ANC)


def fn(path, s, subj):
    # A3: before lfs find --device the tool and its tests are not there
    if C156 in ANC and C160 not in ANC:
        if path == TOOL:
            if s is not None:
                HITS.setdefault(subj, []).append('A3-tool-rm')
            return None
        if path in TU or path == CS:
            b = base(path)
            if s != b:
                HITS.setdefault(subj, []).append('A3-base:' + path.split('/')[-1])
            return b
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
    for tag, p, o, f, gate in R_FN:
        if p != path or o not in s or not gate_ok(gate):
            continue
        assert s.count(o) == 1, (tag, subj, s.count(o))
        n = f(s)
        if n in s:
            continue
        s = s.replace(o, n)
        HITS.setdefault(subj, []).append(tag)
    return s


# ---------------------------------------------------------------- messages
M = {
    'm156-artem': (
        '''Classification and size, with fixes by Artem Blagodarenko:
''',
        '''Classification and size, by Artem Blagodarenko:
'''),
    'm156-tests': (
        '''run_tests() in lustre/tests/llapi_test_utils.{c,h} is split, so that
run_test_tbl() can take a device instead of a mount point.

conf-sanity test_300a scans the MDT and test_300b the OST, each
checking its server's version. Each fails, not skips, if the scanner is
missing, because that is a broken install; 300b skips a ZFS,
unreachable or older OST rather than passing without scanning it.
''',
        '''The tests come with lfs find --device, which runs this scan from the
command line.
'''),
    'm159-printf': (
        '''printf_format_want() decides the %p refusal and what a format needs to
read, so "-printf %i" does not read a layout.
''',
        '''printf_format_want() decides the %p refusal and what a format needs to
read, so "-printf %i" does not read a layout.

-printf gains %LO, the FIDs of a file's OST objects: comma-separated,
one list in brackets per component, as %Lo lists their indices. It
works on a walk too, from the same layout, through a new internal
layout_ost_fid_get(); a stripe with no object yet is left out. On an
OST scan %LO prints the data object's own FID. %LF prints nothing for
an OST data object: the FID a user knows is the file's, on the MDT.
sanity 56Ea checks %LO against lfs getstripe -y.
'''),
    'm160-tests': (
        '''conf-sanity 300 runs lfs find over the scan that it already compares
with a client walk. "--type f" must return every regular file that the
client listed, and no directory. Both sides print FIDs with
"-printf %LF", and the temporary files go through stack_trap. The test
also checks --device=VALUE, both ways of naming a target twice, and
that --internal only adds objects. test_300c runs --local with --ost
''',
        '''conf-sanity test_300a stops the filesystem and compares lfs find
--device on the MDT with a client walk made before: every FID the
client saw must be on the device, "--type f" must return every regular
file and no directory, and -printf %LO must give each file the OST
object FIDs that the client saw. Both sides print with -printf, and the
temporary files go through stack_trap. test_300b writes files on ost1,
and a scan of the stopped OST must print each one's object FID with
%LO. Both also run llapi_scan_device_test, for what lfs find does not
show: the scan statistics, thread counts, the pre-filter and bad
arguments. Each fails, not skips, if the scanner is missing, because
that is a broken install. run_tests() in
lustre/tests/llapi_test_utils.{c,h} is split, so that run_test_tbl()
can take a device instead of a mount point. test_300a also checks
--device=VALUE, both ways of naming a target twice, and that
--internal only adds objects. test_300c runs --local with --ost
'''),
    'm288-owner': (
        '''scan reads it from the LMA buffer that it already has. Measured on an
OST formatted with -I 256: without this, none of 33 objects had an
owner.
''',
        '''scan reads it from the LMA buffer that it already has. Measured on an
OST formatted with -I 256: without this, none of 33 objects had an
owner.

-printf %LF on an OST data object prints that owner FID, the FID a
user knows, and nothing for an object no file owns yet; %LO still
prints the object's own. lfs-find.1 and llapi_find_device.3 say so,
and conf-sanity 300b checks both against what the client printed
before the OST was stopped.
'''),
}


def msgfn(msg, subj):
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
