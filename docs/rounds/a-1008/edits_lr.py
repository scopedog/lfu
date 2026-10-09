# lreview round (user: "Fix all", 10-08).  exec'd by rebuild.py, which
# defines edit(), para(), rep() and the C* indexes.
LH = 'include/lustre/lustreapi.h'
LFD3 = 'Documentation/man3/llapi_find_device.3'
LFS3 = 'Documentation/man3/llapi_find_since.3'
LSD3 = 'Documentation/man3/llapi_scan_device.3'
LRP3 = 'Documentation/man3/llapi_scan_rec_path.3'
LSC = 'lustre/utils/liblustreapi_scan.c'
TMK = 'lustre/tests/Makefile.am'
CLT = 'lustre/tests/llapi_scan_changelog_test.c'

# -- 68159 #2: Data-on-MDT's stripe count is a real 0
edit(C159, PF, '	uint64_t str_cnt, str_size, idx;',
     '	uint64_t str_cnt, str_size, idx, pattern;', 'lr2 decl')
edit(C159, PF, """			if (str_cnt == LLAPI_LAYOUT_DEFAULT)
				goto format_done;
			*wrote = snprintf(buffer, size, "%llu",
					  (unsigned long long)str_cnt);""",
     """			/* but Data-on-MDT has a real count of 0 */
			if (str_cnt == LLAPI_LAYOUT_DEFAULT &&
			    llapi_layout_pattern_get(layout, &pattern) == 0 &&
			    pattern == LLAPI_LAYOUT_MDT)
				str_cnt = 0;
			if (str_cnt == LLAPI_LAYOUT_DEFAULT)
				goto format_done;
			*wrote = snprintf(buffer, size, "%llu",
					  (unsigned long long)str_cnt);""", 'lr2 dom')
# -- 68159 #3: the index is never the default here
edit(C159, PF, """				goto format_done;
			}
			/* the default, as above, is not an index to print */
			if (idx == LLAPI_LAYOUT_DEFAULT)
				goto format_done;
			*wrote = snprintf(buffer, size, "%llu",
					  (unsigned long long)idx);""",
     """				goto format_done;
			}
			*wrote = snprintf(buffer, size, "%llu",
					  (unsigned long long)idx);""", 'lr3 idx')
# -- 68159 #4: %p never prints NULL
edit(C159, PF, """	case 'p':	/* Path name of file */
		*wrote = snprintf(buffer, size, "%s", path);""",
     """	case 'p':	/* Path name of file */
		/* the two format parsers can disagree: never print NULL */
		if (path == NULL)
			break;
		*wrote = snprintf(buffer, size, "%s", path);""", 'lr4 p')

# -- 68288 #5: a striped directory's shards are not reported
edit(C288, PF, """	rc = find_device_prefilter(rec, param, &checked_type, &entry);""",
     """	/* a shard is part of its striped directory: the master answers */
	if (rec->lfsr_valid & LLAPI_SCAN_LMV_SHARD)
		return 0;

	rc = find_device_prefilter(rec, param, &checked_type, &entry);""",
     'lr5 shard')
edit(C288, LFD3, r"""delivers \(em and is counted undecided rather than answered.
.SH RETURN VALUES""", r"""delivers \(em and is counted undecided rather than answered.
.LP
A striped directory has a shard on each MDT it is striped over. The shards are
not reported: the master answers for the directory, once, as a walk does.
.SH RETURN VALUES""", 'lr5 man')
# -- 68288 #6: user_fid2path is a mount option
edit(C288, LF1, """.B CAP_DAC_READ_SEARCH
unless
.B llite.*.user_fid2path
is set, and a FID that cannot be looked up is an error, not a missing name.""",
     """.B CAP_DAC_READ_SEARCH
unless the client was mounted with
.BR "-o user_fid2path" ,
and a FID that cannot be looked up is an error, not a missing name.""",
     'lr6 man1')
edit(C288, LRP3, """.B CAP_DAC_READ_SEARCH
unless
.B llite.*.user_fid2path
is set.""", """.B CAP_DAC_READ_SEARCH
unless the client was mounted with
.BR "-o user_fid2path" .""", 'lr6 man3')
edit(C288, LSC, ' *   CAP_DAC_READ_SEARCH unless llite.*.user_fid2path is set',
     ' *   CAP_DAC_READ_SEARCH unless the client was mounted with -o user_fid2path',
     'lr6 kdoc')
# -- 68288 #7: two -EINVAL cases
edit(C288, LFD3, """longer than 4096 bytes, or longer than its own definition with a byte past the
end of it set.""", """longer than 4096 bytes, or longer than its own definition with a byte past the
end of it set. Also when
.I fp_paths
is set together with
.IR fp_fid2path_mnt ,
or when
.I fp_fid2path_mnt
is a subdirectory (fileset) mount.""", 'lr7 einval')
# -- 68288 #8: the owner FID can come from the LMA
edit(C288, LH, """	 * The MDT FID of the file an OST data object belongs to, from the
	 * object's own trusted.fid.  It is what names such an object: its""",
     """	 * The MDT FID of the file an OST data object belongs to, from the
	 * object's own trusted.fid, or from trusted.lma where there is none
	 * (an OST with 256-byte inodes).  It is what names such an object: its""",
     'lr8 hdr')
edit(C288, LSD3, """which the object records in its own
.BR trusted.fid .""", """which the object records in its own
.B trusted.fid
(on an OST with 256-byte inodes, in its
.B trusted.lma
instead).""", 'lr8 man')

# -- 68163 #10: Makefile.am comment
edit(C163, TMK, """# backend the library no longer carries.  With plugins it is dlopen'ed and
# there is nothing to link.""", """# ZFS backend, which liblustreapi does not link.  With plugins it is
# dlopen'ed and there is nothing to link.""", 'lr10 mk')

# -- 68415 #11: the rename bits are about the replaced object
edit(C415, SC, """		if (fid_is_sane(&rn->cr_sfid) && !replaced) {
			o->co_src_fid = rn->cr_sfid;""",
     """		if (fid_is_sane(&rn->cr_sfid) && !replaced) {
			/* both bits describe the replaced target */
			if (r->cr_type != CL_MIGRATE)
				o->co_flags &= ~(CLF_RENAME_LAST |
						 CLF_RENAME_LAST_EXISTS);
			o->co_src_fid = rn->cr_sfid;""", 'lr11 code')
edit(C415, LC3, """carries the source fields; the replaced object did not come from
.IR a .""", """carries the source fields; the replaced object did not come from
.IR a .
.B CLF_RENAME_LAST
and
.B CLF_RENAME_LAST_EXISTS
describe the replaced object, so only its record carries them.""",
     'lr11 man')
# -- 68415 #13: the burst is made of MDT events
edit(C415, CLT, """/* A workload with one of each event this test reasons about. */
static __u64 make_events(const char *dir)""",
     """/* the file the burst is made on, for test1 */
static struct lu_fid burst_fid;

/* A workload with one of each event this test reasons about. */
static __u64 make_events(const char *dir)""", 'lr13 global')
edit(C415, CLT, """	/* a burst: object mode must make one record of this */
	for (i = 0; i < 20; i++) {
		if (write(fd, "x", 1) != 1)
			break;
		fsync(fd);
	}
	close(fd);""", """	/*
	 * A burst: object mode must make one record of this.  A write is no
	 * Changelog event, a chmod is: each one is a CL_SETATTR.
	 */
	if (llapi_fd2fid(fd, &burst_fid) < 0)
		memset(&burst_fid, 0, sizeof(burst_fid));
	for (i = 0; i < 20; i++) {
		if (fchmod(fd, i % 2 ? 0644 : 0640) < 0)
			break;
	}
	close(fd);""", 'lr13 burst')
edit(C415, CLT, """	param_init(&sc);
	rc = llapi_scan_changelog(&sc, cl_cb, &ev);
	ASSERTF(rc == 0, "event mode failed: %s", strerror(-rc));
""", """	ev.cr_target = burst_fid;
	ob.cr_target = burst_fid;
	param_init(&sc);
	rc = llapi_scan_changelog(&sc, cl_cb, &ev);
	ASSERTF(rc == 0, "event mode failed: %s", strerror(-rc));
""", 'lr13 target')
edit(C415, CLT, """	printf("  %u events collapse to %u objects\\n",
	       ev.cr_records, ob.cr_records);""", """	ASSERTF(burst_fid.f_seq != 0, "the burst's file has no FID");
	ASSERTF(ev.cr_target_hits >= 20,
		"%u events on the burst's file, expected 20 or more",
		ev.cr_target_hits);
	ASSERTF(ob.cr_target_hits == 1,
		"the burst's file arrived %u times in object mode",
		ob.cr_target_hits);

	printf("  %u events collapse to %u objects\\n",
	       ev.cr_records, ob.cr_records);""", 'lr13 assert')

# -- 68417 #14: --since is refused over a target scan
REF_OLD = """is refused too, because its format ends in
.BR %p .
.PP
.BR llapi_find_device (3)
describes each difference in full."""
REF_NEW = """is refused too, because its format ends in
.BR %%p .
.TP
%s
%s refused too: a target scan reads no changelog.
.PP
.BR llapi_find_device (3)
describes each difference in full."""
edit(C417, LF1, REF_OLD, REF_NEW % ('.B --since', 'This is'), 'lr14 man1',
     until=C418)
edit(C418, LF1, REF_OLD, REF_NEW % ('.BR --since ", " --changelog', 'These are'),
     'lr14 man1 418', until=C419)
edit(C419, LF1, REF_OLD,
     REF_NEW % ('.BR --since ", " --since-cookie ", " --changelog', 'These are'),
     'lr14 man1 419')
NS_OLD = """.BR --mindepth ", " --threads ).
.B --ost
over an MDT and"""
NS_NEW = """.BR --mindepth ", " --threads ).
Nor does it have a changelog
.RI ( %s ).
.B --ost
over an MDT and"""
edit(C417, LFD3, NS_OLD, NS_NEW % 'fp_since_kind', 'lr14 man3', until=C418)
edit(C418, LFD3, NS_OLD, NS_NEW % 'fp_since_kind ", " fp_changelog_mdt',
     'lr14 man3 418', until=C419)
edit(C419, LFD3, NS_OLD,
     NS_NEW % 'fp_since_kind ", " fp_changelog_mdt ", " fp_since_cookie',
     'lr14 man3 419')
# -- 68417 #15: the header says what the library takes
edit(C417, LH, """#define LLAPI_SINCE_INDEX	1	/* a bare integer: one MDT's cr_index */
/* a duration, a timestamp, or @seconds */
#define LLAPI_SINCE_TIME	2""", """#define LLAPI_SINCE_INDEX	1	/* fp_since_index: one MDT's cr_index */
/* fp_since_time: an absolute time, in seconds since the epoch */
#define LLAPI_SINCE_TIME	2""", 'lr15 hdr')
# -- 68417 #16: an unknown kind is refused
edit(C417, PF, """	if (param->fp_since_kind == LLAPI_SINCE_NONE""",
     """	/* a kind this library does not know is not read as "all" */
	if (param->fp_since_kind > LLAPI_SINCE_TIME)
		return -EINVAL;
	if (param->fp_since_kind == LLAPI_SINCE_NONE""", 'lr16 code')
edit(C417, LFS3, """.I param
is NULL,
.I fp_since_kind
is
""", """.I param
is NULL,
.I fp_since_kind
is a value this library does not know, or it is
""", 'lr16 man')

# -- 68419 #21: a file that is not a cookie is not overwritten
edit(C419, PF, """	struct stat st;
	FILE *fp;
	int fd;
	int rc;

	rc = find_ck_escape(rootesc, sizeof(rootesc), root);""",
     """	struct stat st;
	int known = 0;
	int lines = 0;
	FILE *fp;
	int fd;
	int rc;

	rc = find_ck_escape(rootesc, sizeof(rootesc), root);""", 'lr21 decl')
edit(C419, PF, """		int pos;

		/*
		 * The header names the filesystem the file was written for.""",
     """		int pos;

		/* a line with text on it, for the not-a-cookie test below */
		if (line[strspn(line, " \\t\\n")] != '\\0' && line[0] != '#')
			lines++;

		/*
		 * The header names the filesystem the file was written for.""",
     'lr21 count')
edit(C419, PF, """				fclose(fp);
				return -EINVAL;
			}
			continue;
		}
""", """				fclose(fp);
				return -EINVAL;
			}
			known++;
			continue;
		}
""", 'lr21 header')
edit(C419, PF, """		starts[mdt] = idx;
	}

	/* a read error must not read as a short cookie, i.e. a first run */
	rc = ferror(fp) ? -EIO : 0;
	fclose(fp);
	return rc;""", """		starts[mdt] = idx;
		known++;
	}

	/* a read error must not read as a short cookie, i.e. a first run */
	rc = ferror(fp) ? -EIO : 0;
	fclose(fp);
	/*
	 * Text, and none of it ours: some other file, which the rewrite would
	 * replace.  An empty file is a first run, and anchors written by hand
	 * are read.
	 */
	if (rc == 0 && lines > 0 && known == 0) {
		llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -EINVAL,
			    "'%s' is not a cookie: no line in it is one lfs find writes",
			    file);
		rc = -EINVAL;
	}
	return rc;""", 'lr21 refuse')
edit(C419, PF, """ * reached.  A line is "<mdtname> <index>"; anything else is ignored, so a
 * comment or a blank line costs the read nothing -- but the rewrite emits
 * the header and the anchors and nothing else, so it does not survive the
 * next run.  The file is this call's to own, not a place to annotate.""",
     """ * reached.  A line is "<mdtname> <index>"; anything else is ignored, so a
 * comment or a blank line costs the read nothing -- but the rewrite emits
 * the header and the anchors and nothing else, so it does not survive the
 * next run.  The file is this call's to own, not a place to annotate.  A
 * file with text in it and no header or anchor at all is refused.""",
     'lr21 cmt')
edit(C419, LFS3, """regular file (a symbolic link is not one), or that was written for another
filesystem or another search root.""", """regular file (a symbolic link is not one), that was written for another
filesystem or another search root, or that has text in it but no line that
.B lfs find
writes.""", 'lr21 man')
# -- 68419 #24: the cookie's own errors
edit(C419, LFS3, """.BR realpath (3)'s
answer, and not the one for a path outside Lustre.""", """.BR realpath (3)'s
answer, and not the one for a path outside Lustre.
.IP
The errors from opening, creating or renaming
.I fp_since_cookie
are returned as they came, so
.BR -ENOENT ,
.B -EACCES
and
.B -EROFS
can also be about the cookie.""", 'lr24 man')
# -- 68419 #25: the header says what the field holds
edit(C419, LH, """	/* --since-cookie: per-MDT indexes from a previous run, rewritten at
	 * the end.  One anchor per MDT, so the one that holds on all of them.
	 */""", """	/* --since-cookie: the pathname of a file of per-MDT changelog
	 * indexes, read before the search and rewritten after it.  NULL: not
	 * given.
	 */""", 'lr25 hdr')
edit(C419, LH, """ * param->fp_since_kind says where to start.
 */
int llapi_find_since(""", """ * param->fp_since_kind or param->fp_since_cookie says where to start.
 */
int llapi_find_since(""", 'lr25 proto')

# -- 69443 #26: the first MDT is checked again too
edit(C443, PF, """		 * find_cookie_check() ran before any MDT was read, so a purge
		 * on this MDT while an earlier one was being read got past it.
		 * Ask again just before reading: one record, as there.  The""",
     """		 * find_cookie_check() ran before any MDT was read, so a purge
		 * on this MDT since then got past it -- for the first MDT,
		 * during the rest of the check.  Ask again just before
		 * reading: one record, as there.  The""", 'lr26 cmt')
edit(C443, PF, """		if (i > 0 && param->fp_since_cookie != NULL &&
		    starts[mdts[i]] != 0) {""", """		if (param->fp_since_cookie != NULL &&
		    starts[mdts[i]] != 0) {""", 'lr26 code')
edit(C443, LF1, """and the purge test runs again just before each later MDT is read: a purge
that reaches it while an earlier one is being read is refused then.""",
     """and the purge test runs again just before each MDT is read: a purge
that reaches it after the first test is refused then.""", 'lr26 man1')
edit(C443, LFS3, """scanned, and the purge test runs again just before each later MDT is read:
a clear that lands on it while an earlier one is being read ends the call""",
     """scanned, and the purge test runs again just before each MDT is read:
a clear that lands on it after the first test ends the call""", 'lr26 man3')

# -- 69500 #27/#28: name the range that is missing
edit(F_GAP, LF1, """.I INDEX
the records before it are certainly missing from the answer. For""",
     """.I INDEX
the records from it up to where the log now starts are certainly missing from
the answer. For""", 'lr27 man')
edit(F_GAP, PF, """		/* exact: the records before the oldest were in the window */
		if (oldest > param->fp_since_index)
			llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
				    "'%s' has been cleared past the --since anchor: its oldest record is %llu, and the records before it are not in the answer",
				    mdtname, (unsigned long long)oldest);""",
     """		/* exact: anchor to oldest - 1 were in the window (0 is 1) */
		if (oldest > param->fp_since_index)
			llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
				    "'%s' has been cleared past the --since anchor: records %llu to %llu are not in the answer",
				    mdtname, (unsigned long long)
				    (param->fp_since_index ?: 1),
				    (unsigned long long)(oldest - 1));""", 'lr28 msg')

# -- renames (#12, #23): word-wise, from the commit that adds the name up
RENAMES = [(C415, 'LLAPI_SCAN_JOBID', 'LLAPI_SCAN_EVENT_JOBID'),
           (C415, 'lfsr_jobid', 'lfsr_event_jobid'),
           (C419, 'find_ck_escape', 'find_cookie_escape'),
           (C419, 'FIND_CK_W_', 'FIND_COOKIE_WIDTH_'),
           (C419, 'FIND_CK_W', 'FIND_COOKIE_WIDTH')]
# after the renames: keep the struct line inside 80 columns
POST = [(C415, LH, '*lfsr_event_jobid;\t/* with LLAPI_SCAN_EVENT_JOBID */',
         '*lfsr_event_jobid; /* LLAPI_SCAN_EVENT_JOBID */', 'post jobid')]


def m_159(m):
    return rep(m, '''Three -printf answers were wrong in a walk too. For a layout that only
says "the default", the stripe count, size and index printed
LLAPI_LAYOUT_DEFAULT. They now print nothing. %Lo skips a component''',
               '''Three -printf answers were wrong in a walk too. For a layout that only
says "the default", the stripe count and size printed
LLAPI_LAYOUT_DEFAULT. They now print nothing, except that a
Data-on-MDT component's count prints 0, as lfs getstripe says.
%Lo skips a component''',
               'm159 default')


def m_288(m):
    return para(m, '''A striped directory's shards are not reported: the master answers
for the directory once, as a walk does.''', 'm288')


def m_163(m):
    return rep(m, 'LU-20613 llapi: ZFS backend for llapi_scan_device\n',
               'LU-20613 llapi: add a ZFS backend to llapi_scan_device()\n',
               'm163 subject')


def m_415(m):
    return para(m, '''CLF_RENAME_LAST and CLF_RENAME_LAST_EXISTS describe the replaced
target of a rename, so the moved object's record does not carry them.''',
                'm415')


def m_418_b(m):
    m = m_418(m)
    return rep(m, '''- find_since_pick() puts a link's basename into the record only for
  --since.  Under --changelog the recorded name stays, and the link''',
               '''- find_since_pick() puts a link's basename into the record only for
  --since, or for a --changelog record that carried no name.  Under
  --changelog the recorded name stays, and the link''',
               'm418 pick')


def m_419_b(m):
    m = m_419(m)
    return rep(m, '''"lfs find --since-cookie ck > out" on a full filesystem would lose
the matches, advance past their records and exit 0.''',
               '''"lfs find --since-cookie ck > out" on a full filesystem would lose
the matches, advance past their records and exit 0.  When stdout is
a regular file it is also fsync()ed, and a failed sync holds the
anchors and returns -EIO.''', 'm419 fsync')


def m_443(m):
    return rep(m, '''So llapi_find_since() reads the oldest record again just before each
later MDT is scanned, through find_cookie_purged(), the purge test''',
               '''So llapi_find_since() reads the oldest record again just before each
MDT is scanned, the first one too, through find_cookie_purged(), the
purge test''', 'm443')

# -- 68288 #5 (lab): the shard bit needs trusted.lmv read, so ask for it
edit(C288, 'lustre/utils/liblustreapi_scan_device.c',
     """	if (want & LLAPI_SCAN_LMV)
		xa |= LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LMV);""",
     """	if (want & (LLAPI_SCAN_LMV | LLAPI_SCAN_LMV_SHARD))
		xa |= LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LMV);""", 'lr5 xa')
edit(C288, PF, """	if (param->fp_fid2path_mnt != NULL || param->fp_paths)
		want |= LLAPI_SCAN_OWNER | LLAPI_SCAN_PARENT |
			LLAPI_SCAN_LINKEA | LLAPI_SCAN_LMV_SHARD;

	return want;""", """	if (param->fp_fid2path_mnt != NULL || param->fp_paths)
		want |= LLAPI_SCAN_OWNER | LLAPI_SCAN_PARENT |
			LLAPI_SCAN_LINKEA | LLAPI_SCAN_LMV_SHARD;
	/* find_device_cb() skips a shard, so it has to know one */
	want |= LLAPI_SCAN_LMV_SHARD;

	return want;""", 'lr5 want')

# ---- AI round on 68419/68420 PS15 (10-08 evening)
edit(C418, LF1, """An object touched in two separate bursts is delivered twice and printed
twice: coalescing collapses events only within the window a burst spans, and
a second burst is a second event.""", """A burst is the events on one object with no gap of ten minutes or more
between them, and at most about an hour long; on a busy log it can end
sooner. An object touched in two separate bursts is delivered twice and
printed twice: coalescing collapses events only within a burst, and a second
burst is a second event.""", 'ai420 burst')
edit(C419, PF, '	/* one of the two has to have selected this path */',
     '	/* --since, --changelog or a cookie has to have selected this path */',
     'ai419 three')

# ---- AI round on 69501 PS1: STATX_NLINK means the same in every scanner
edit(F_NLINK, LSC, """		/* a directory's count is its subdirectories, not its names */
		if (nlink != 0 && !S_ISDIR(mode)) {""",
     """		/* a directory's too, as every scanner gives it */
		if (nlink != 0) {""", 'ai501 lib')
edit(F_NLINK, PF, """	if ((rec->lfsr_stx.stx_mask & STATX_MODE) &&
	    S_ISDIR(rec->lfsr_stx.stx_mode))
		return false;
	return true;
}""", """	/* a directory's count is its subdirectories, not its names */
	if ((rec->lfsr_stx.stx_mask & (STATX_TYPE | STATX_MODE)) &&
	    S_ISDIR(rec->lfsr_stx.stx_mode))
		return false;
	return true;
}""", 'ai501 consumer')
edit(F_NLINK, 'Documentation/man3/llapi_scan_fid.3',
     """and, for anything but a directory, the link count in""",
     """and the link count in""", 'ai501 man1')
edit(F_NLINK, 'Documentation/man3/llapi_scan_fid.3',
     """before trusting the count: it is clear for a directory, when
.BR statx (2)
did not report one, and when the count read back was 0, as for a file
unlinked after its FID was resolved.""",
     """before trusting the count: it is clear when
.BR statx (2)
did not report one, and when the count read back was 0, as for a file
unlinked after its FID was resolved. A directory's count is given as the
other scanners give it; it counts subdirectories, not names.""", 'ai501 man2')
edit(F_NLINK, 'lustre/tests/llapi_scan_test.c',
     """	/* a directory's link count counts subdirectories, so it is left out */
	memset(&fb, 0, sizeof(fb));
	rc = llapi_scan_fid(mnt_fd, mnt, &dfid, &sp, fid_cb, &fb);
	ASSERTF(rc == 0 && fb.fb_peek.fp_count == 1 &&
		!(fb.fb_peek.fp_stx_mask & STATX_NLINK),""",
     """	/* a directory's link count is given too, as other scanners give it */
	memset(&fb, 0, sizeof(fb));
	rc = llapi_scan_fid(mnt_fd, mnt, &dfid, &sp, fid_cb, &fb);
	ASSERTF(rc == 0 && fb.fb_peek.fp_count == 1 &&
		(fb.fb_peek.fp_stx_mask & STATX_NLINK),""", 'ai501 test')


def m_nlink(m):
    return rep(m, '''for and, for anything but a directory, the link count. A directory has
one name, and its link count counts its subdirectories. The statx()''',
               '''for and the link count, a directory's included, as the other
scanners give it; the filter tests the type itself. The statx()''',
               'm501')
