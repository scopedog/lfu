#!/usr/bin/env python3
# Fold fix-1009's two fixups -- 68417's _ONCE-loss fix and 68415's _FOLLOW
# clear error -- into their commits and carry them up the stack.  Each new
# commit = the ORIGINAL commit's tree + the edits, so no merge is resolved
# by hand.  The tip must equal fix-1009's tree.
# Usage: fold.py [--dry]   (in ~/lfs-fix-1007; makes branch fold-1009)
import subprocess, sys, re
R = '/home/nishida/lfs-fix-1007'
BASE = 'f20ad1ea81'            # 68288, below 68415
FIRST_68417 = '0675d64536'
OLD_TIP = 'a009cfea7b'
FIX = 'fix-1009'
F = 'lustre/utils/liblustreapi_pfind.c'

def git(*a, inp=None):
    return subprocess.run(['git', '-C', R] + list(a), input=inp,
                          capture_output=True, text=True, check=True).stdout

def rep(s, a, b, what):
    if s.count(a) != 1:
        raise SystemExit('%s: %d matches' % (what, s.count(a)))
    return s.replace(a, b)

def T(s):
    # find_ctx: an out flag, last member
    i = s.index('struct find_ctx {\n'); j = s.index('\n};\n', i)
    s = s[:j] + '\n\tbool\t\t\t fc_matched;\t/* out: reached print */' + s[j:]
    s = rep(s, 'print:\n\tif (param->fp_skip_percent && find_skip_file(param))',
            'print:\n\tfc->fc_matched = true;\n'
            '\tif (param->fp_skip_percent && find_skip_file(param))', 'print')
    s = rep(s, """	/* FIDs already taken, across MDTs: _ONCE's set is per MDT */
	void			*fss_seen;
	bool			 fss_multi_mdt;
};
""", """	/* struct find_since_obj per FID, across MDTs */
	void			*fss_seen;
	bool			 fss_matched;	/* reached print */
};

/*
 * A candidate already looked up.  Done once it was printed or cannot be
 * looked up again usefully.  A rejected one is not done: a change made
 * after its lookup, read later in the same run, may make it match.
 */
struct find_since_obj {
	struct lu_fid		fso_fid;	/* first: find_fid_cmp() key */
	bool			fso_done;
	time_t			fso_looked;	/* when the lookup started */
};
""", 'state')
    i = s.index('static int find_since_rec_cb(')
    a = '\trc = find_decide(&fc, param);\n\tif (fd >= 0)\n\t\tclose(fd);\n\n\treturn rc;\n}'
    j = s.index(a, i)
    s = s[:j] + a.replace('\n\n\treturn rc;',
        '\n\tif (fc.fc_matched)\n\t\tst->fss_matched = true;\n\n\treturn rc;') + s[j + len(a):]
    # filter_cb header: 68417's wording, then 68419's
    if ' * LLAPI_SCAN_CL_F_ONCE an object already delivered is dropped before the\n * callback.\n' in s:
        s = rep(s, """ * It is asked here rather than in the callback because sc_filter sees each
 * delivery before any lookup, and the callback does not: under
 * LLAPI_SCAN_CL_F_ONCE an object already delivered is dropped before the
 * callback.
""", """ * It is asked here rather than in the callback because sc_filter sees each
 * delivery before any lookup, and the callback does not: an object already
 * printed is dropped before the lookup.
""", 'hdr1')
    else:
        s = rep(s, """ * -- and under LLAPI_SCAN_CL_F_ONCE an object already delivered is dropped
 * before the callback too.
""", """ * -- and an object already printed is dropped before the lookup too.
""", 'hdr3')
    s = rep(s, """	 * Refused here and not in the callback because _ONCE records what
	 * the callback was handed: a burst from before the window taken as a
	 * delivery would suppress the burst inside it that follows, and turn
	 * a duplicate line into a missing one.
""", """	 * Refused here and not in the callback, so a burst from before the
	 * window is never looked up: it would print an object that has not
	 * changed inside it.
""", 'refused')
    s = rep(s, """/*
 * Whether another MDT's log already gave this FID.  A remote mkdir or a
 * cross-MDT rename puts one object in two logs.
 *
 * Return: 1 if seen, 0 if not (now recorded), or -ENOMEM.
 */
static int find_since_seen(struct find_since_state *st,
			   const struct lu_fid *fid)
{
	struct lu_fid *key;
	void *node;

	key = malloc(sizeof(*key));
	if (key == NULL)
		return -ENOMEM;
	*key = *fid;
	node = tsearch(key, &st->fss_seen, find_fid_cmp);
	if (node == NULL) {
		free(key);
		return -ENOMEM;
	}
	if (*(struct lu_fid **)node != key) {
		free(key);
		return 1;
	}
	return 0;
}
""", """/*
 * Find or add @fid in the candidates of this run, across MDTs: a remote
 * mkdir or a cross-MDT rename puts one object in two logs.
 *
 * Return: 1 if new, 0 if seen before, or -ENOMEM.
 */
static int find_since_obj(struct find_since_state *st,
			  const struct lu_fid *fid, struct find_since_obj **obj)
{
	struct find_since_obj *key;
	void *node;

	key = calloc(1, sizeof(*key));
	if (key == NULL)
		return -ENOMEM;
	key->fso_fid = *fid;
	node = tsearch(key, &st->fss_seen, find_fid_cmp);
	if (node == NULL) {
		free(key);
		return -ENOMEM;
	}
	*obj = *(struct find_since_obj **)node;
	if (*obj != key) {
		free(key);
		return 0;
	}
	return 1;
}
""", 'seen')
    if '\tif (st->fss_multi_mdt) {\n' in s:          # 68417 itself
        s = rep(s, """	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp) };
	int rc;

	if (!(rec->lfsr_valid & LLAPI_SCAN_FID))
""", """	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp) };
	struct find_since_obj *obj = NULL;
	__u64 undecided;
	int rc;

	if (!(rec->lfsr_valid & LLAPI_SCAN_FID))
""", 'decl1')
        s = rep(s, """	if (st->fss_multi_mdt) {
		rc = find_since_seen(st, &rec->lfsr_fid);
		if (rc != 0)
			return rc < 0 ? rc : 0;
	}

	/* the window cut is find_since_filter_cb()'s, before this */
	st->fss_cand++;
	sp.lfsp_want = st->fss_want;

	st->fss_cb_called = false;
	rc = llapi_scan_fid(st->fss_mnt_fd, st->fss_mnt_path, &rec->lfsr_fid,
			    &sp, find_since_rec_cb, st);
""", """	/*
	 * Each object once, unless it was rejected and changed after its
	 * lookup: the anchor moves past that change either way.
	 */
	rc = find_since_obj(st, &rec->lfsr_fid, &obj);
	if (rc < 0)
		return rc;
	if (obj->fso_done)
		return 0;
	/*
	 * The lookup saw every event before it started.  The clocks are
	 * compared as the --since window already compares them.
	 */
	if (rc == 0 && (rec->lfsr_valid & LLAPI_SCAN_EVENT) &&
	    rec->lfsr_event_time < obj->fso_looked)
		return 0;
	/* the window cut is find_since_filter_cb()'s, before this */
	if (rc == 1)
		st->fss_cand++;
	sp.lfsp_want = st->fss_want;

	st->fss_cb_called = false;
	st->fss_matched = false;
	undecided = st->fss_undecided;
	obj->fso_looked = time(NULL);
	rc = llapi_scan_fid(st->fss_mnt_fd, st->fss_mnt_path, &rec->lfsr_fid,
			    &sp, find_since_rec_cb, st);
	/* anything but a rejection is final */
	if (rc != 0 || st->fss_matched || st->fss_undecided != undecided)
		obj->fso_done = true;
""", 'cand1')
        s = rep(s, """		/*
		 * _ONCE for --since and not for --changelog: coalescing
		 * reduces an object to one record only within sc_min_age, so
		 * over a longer window an object touched in two bursts
		 * arrives twice, is looked up twice and prints its path
		 * twice -- where a walk prints it once.  --changelog reports
		 * the log, and a second burst is a second thing that
		 * happened, so it keeps both.
		 */
		sc.sc_flags = LLAPI_SCAN_CL_F_COALESCE | LLAPI_SCAN_CL_F_ONCE;
""", """		/*
		 * Not _ONCE: it would drop a later burst of an object the
		 * callback rejected.  find_since_cand_cb() keeps its own set.
		 */
		sc.sc_flags = LLAPI_SCAN_CL_F_COALESCE;
""", 'once1')
    else:
        s = rep(s, """	struct find_cl_merge m = { .fcm_st = st, .fcm_cl = rec };
	int rc;
""", """	struct find_cl_merge m = { .fcm_st = st, .fcm_cl = rec };
	struct find_since_obj *obj = NULL;
	__u64 undecided;
	int rc;
""", 'decl2')
        s = rep(s, """	if (st->fss_multi_mdt && !st->fss_as_recorded) {
		rc = find_since_seen(st, &rec->lfsr_fid);
		if (rc != 0)
			return rc < 0 ? rc : 0;
	}

	/* the window cut is find_since_filter_cb()'s, before this */
	st->fss_cand++;
""", """	/*
	 * Each object once, unless it was rejected and changed after its
	 * lookup: the anchor moves past that change either way.
	 */
	if (!st->fss_as_recorded) {
		rc = find_since_obj(st, &rec->lfsr_fid, &obj);
		if (rc < 0)
			return rc;
		if (obj->fso_done)
			return 0;
		/*
		 * The lookup saw every event before it started.  The clocks
		 * are compared as the --since window already compares them.
		 */
		if (rc == 0 && (rec->lfsr_valid & LLAPI_SCAN_EVENT) &&
		    rec->lfsr_event_time < obj->fso_looked)
			return 0;
		/* the window cut is find_since_filter_cb()'s, before this */
		if (rc == 1)
			st->fss_cand++;
	} else {
		st->fss_cand++;
	}
""", 'cand2')
        call = """		rc = llapi_scan_fid(st->fss_mnt_fd, st->fss_mnt_path,
				    &rec->lfsr_fid, &sp, find_since_rec_cb, st);
	}
"""
        s = rep(s, call, """		st->fss_matched = false;
		undecided = st->fss_undecided;
		obj->fso_looked = time(NULL);
		rc = llapi_scan_fid(st->fss_mnt_fd, st->fss_mnt_path,
				    &rec->lfsr_fid, &sp, find_since_rec_cb, st);
		/* anything but a rejection is final */
		if (rc != 0 || st->fss_matched ||
		    st->fss_undecided != undecided)
			obj->fso_done = true;
	}
""", 'call2')
        s = rep(s, """		/*
		 * _ONCE for --since and not for --changelog: coalescing
		 * reduces an object to one record only within sc_min_age, so
		 * over a longer window an object touched in two bursts
		 * arrives twice, is looked up twice and prints its path
		 * twice -- where a walk prints it once.  --changelog reports
		 * the log, and a second burst is a second thing that
		 * happened, so it keeps both.
		 */
		sc.sc_flags = LLAPI_SCAN_CL_F_COALESCE;
		if (!st.fss_as_recorded)
			sc.sc_flags |= LLAPI_SCAN_CL_F_ONCE;
""", """		/*
		 * Not _ONCE: it would drop a later burst of an object the
		 * callback rejected.  find_since_cand_cb() keeps its own set.
		 */
		sc.sc_flags = LLAPI_SCAN_CL_F_COALESCE;
""", 'once2')
    s = rep(s, '\tst.fss_multi_mdt = mdt_count > 1;\n', '', 'multi')
    s = rep(s, '/* Stage 5, on a record llapi_scan_fid() filled: the ordinary predicates. */',
            '/* On a record llapi_scan_fid() filled: the ordinary predicates. */', 'stage5a')
    if ' * Stage 5 on a changelog record itself' in s:
        s = rep(s, ' * Stage 5 on a changelog record itself',
                ' * On a changelog record itself', 'stage5b')
    # lreview on the gated version: MDS clock slack, and a noun_verb name
    s = rep(s, '''	time_t			fso_looked;	/* when the lookup started */
};''', '''	time_t			fso_looked;	/* when the lookup started */
};

/* how far the MDS clock may lag this one before a change is missed */
#define FIND_SINCE_CLOCK_SLACK	600''', 'slack')
    old1 = '''	/*
	 * The lookup saw every event before it started.  The clocks are
	 * compared as the --since window already compares them.
	 */
	if (rc == 0 && (rec->lfsr_valid & LLAPI_SCAN_EVENT) &&
	    rec->lfsr_event_time < obj->fso_looked)
		return 0;'''
    new1 = '''	/*
	 * The lookup saw every event before it started.  The event time
	 * is the MDS's, so only one well before it is skipped.
	 */
	if (rc == 0 && (rec->lfsr_valid & LLAPI_SCAN_EVENT) &&
	    rec->lfsr_event_time < obj->fso_looked - FIND_SINCE_CLOCK_SLACK)
		return 0;'''
    old2 = '''		/*
		 * The lookup saw every event before it started.  The clocks
		 * are compared as the --since window already compares them.
		 */
		if (rc == 0 && (rec->lfsr_valid & LLAPI_SCAN_EVENT) &&
		    rec->lfsr_event_time < obj->fso_looked)
			return 0;'''
    new2 = '''		/*
		 * The lookup saw every event before it started.  The event
		 * time is the MDS's, so only one well before it is skipped.
		 */
		if (rc == 0 && (rec->lfsr_valid & LLAPI_SCAN_EVENT) &&
		    rec->lfsr_event_time <
		    obj->fso_looked - FIND_SINCE_CLOCK_SLACK)
			return 0;'''
    s = rep(s, old1, new1, 'gate1') if old1 in s else rep(s, old2, new2, 'gate2')
    s = rep(s, '''static int find_since_obj(struct find_since_state *st,
			  const struct lu_fid *fid, struct find_since_obj **obj)''',
            '''static int find_since_obj_get(struct find_since_state *st,
			      const struct lu_fid *fid,
			      struct find_since_obj **obj)''', 'getdef')
    s = rep(s, 'rc = find_since_obj(st, &rec->lfsr_fid, &obj);',
            'rc = find_since_obj_get(st, &rec->lfsr_fid, &obj);', 'getcall')
    return s

MSG_ADD = '''
Coalescing gives an object one record per burst, so one object can
arrive more than once in a run.  Each FID is kept in one set across
bursts and MDTs.  It is done once it was printed, was gone, could not
be read or was undecided; find_decide() now sets fc_matched at print:
to say so.  A rejected object is looked up again for a later record
whose event is less than FIND_SINCE_CLOCK_SLACK seconds older than
that lookup: a change made after the lookup may make it match, and
the next run starts past it.
'''
def M(msg):
    a = 'under the root and matches.  No new predicates and no second copy of the\nvocabulary.\n'
    return rep(msg, a, a + MSG_ADD, 'msg')

CL = 'lustre/utils/liblustreapi_scan_changelog.c'
CLDOC = 'Documentation/man3/llapi_scan_changelog.3'
def C(s):                       # 68415: a failed clear ends a _FOLLOW stream
    return rep(s, '''		scan_cl_clear(sl, false);

		/* sc_endrec is inclusive''', '''		scan_cl_clear(sl, false);
		/* _FOLLOW never ends, so a failed clear ends it here */
		if ((scl.sc_flags & LLAPI_SCAN_CL_F_FOLLOW) &&
		    sl->sl_clear_rc != 0)
			break;

		/* sc_endrec is inclusive''', 'follow')
def CD(t):
    return rep(t, '''first. The records were delivered, but the log was not cleared past that
point.
''', '''first. The records were delivered, but the log was not cleared past that
point. With
.B LLAPI_SCAN_CL_F_FOLLOW
the stream has no end, so the first failed clear ends it.
''', 'followdoc')

DOC = 'Documentation/man3/llapi_find_since.3'
def D(t):
    return rep(t, '.BR "-o user_fid2path" . A refusal there',
               '.BR "-o user_fid2path" .\nA refusal there', 'man')

dry = '--dry' in sys.argv
commits = git('rev-list', '--reverse', BASE + '..' + OLD_TIP).split()
parent = git('rev-parse', BASE).strip()
first17 = git('rev-parse', FIRST_68417).strip()
in17 = False
for n, c in enumerate(commits):
    in17 = in17 or c == first17
    idx = '/tmp/fold1009.idx'
    subprocess.run(['git', '-C', R, 'read-tree', c],
                   env={'GIT_INDEX_FILE': idx}, check=True)
    edits = [(CL, C), (CLDOC, CD)] + ([(F, T), (DOC, D)] if in17 else [])
    for path, fn in edits:
        new = fn(git('show', '%s:%s' % (c, path)))
        blob = git('hash-object', '-w', '--stdin', inp=new).strip()
        subprocess.run(['git', '-C', R, 'update-index', '--cacheinfo',
                        '100644,%s,%s' % (blob, path)],
                       env={'GIT_INDEX_FILE': idx}, check=True)
    tree = subprocess.run(['git', '-C', R, 'write-tree'], env={'GIT_INDEX_FILE': idx},
                          capture_output=True, text=True, check=True).stdout.strip()
    fmt = lambda f: git('log', '-1', '--format=' + f, c)
    env = {'GIT_AUTHOR_NAME': fmt('%an').strip(), 'GIT_AUTHOR_EMAIL': fmt('%ae').strip(),
           'GIT_AUTHOR_DATE': fmt('%ad').strip(),
           'GIT_COMMITTER_NAME': 'Hiroshi Nishida', 'GIT_COMMITTER_EMAIL': fmt('%ce').strip(),
           'PATH': '/usr/bin:/bin'}
    msg = git('log', '-1', '--format=%B', c)
    if c == first17:
        msg = M(msg)
    parent = subprocess.run(['git', '-C', R, 'commit-tree', tree, '-p', parent],
                            input=msg, env=env, capture_output=True, text=True,
                            check=True).stdout.strip()
    print(n, c[:10], '->', parent[:10], git('log', '-1', '--format=%s', c).strip()[:50])
same = git('rev-parse', parent + '^{tree}').strip() == git('rev-parse', FIX + '^{tree}').strip()
print('TIP', parent, 'tree == fix-1009:', same)
if not dry and same:
    git('branch', '-f', 'fold-1009', parent)
    print('fold-1009 ->', parent[:10])
