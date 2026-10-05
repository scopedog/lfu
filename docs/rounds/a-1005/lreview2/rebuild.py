#!/usr/bin/env python3
# Rebuild fix-1005 with the lreview(2) edits applied to every commit's own
# tree, from the commit that owns each edit upward.  No cherry-picks.
import re, subprocess, sys

REPO = '/home/nishida/lfs-fix-1005'
BASE = 'd2a385f08f'
STACK = ['507b70072f', '5eadb15998', 'c9c29b8112', '40c2602c05',
         'f928042765', '4e7fde3fee', '66b4fa6e08', '8123faeccc',
         'ed7024395f', 'e00b1af3a2', '0130fc912c', '1a82be36df',
         'ae9b2ca3a3']
PF = 'lustre/utils/liblustreapi_pfind.c'
CL = 'lustre/utils/liblustreapi_scan_changelog.c'
SC = 'lustre/utils/liblustreapi_scan.c'


def git(*a, inp=None):
    return subprocess.run(['git', '-C', REPO] + list(a), input=inp,
                          capture_output=True, check=True).stdout


def rep(s, old, new, what):
    n = s.count(old)
    if n != 1:
        raise RuntimeError('%s: %d matches' % (what, n))
    return s.replace(old, new)


# ---- 68159 -------------------------------------------------------------
def e_targets(s):
    s = rep(s, '''	if (param->fp_mdt_uuid != NULL) {
		if (!is_mdt) {
			llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO,
				    -ENOTSUP,
				    "--mdt needs an MDT; '%s' is an OST, whose objects name their MDT only through an FLD lookup",
				    tgt->tt_label);
			return -ENOTSUP;
		}

		indexes =''', '''	/* both refusals first, so every device of a sweep gives the same one */
	if (param->fp_mdt_uuid != NULL && !is_mdt) {
		llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ENOTSUP,
			    "--mdt needs an MDT; '%s' is an OST, whose objects name their MDT only through an FLD lookup",
			    tgt->tt_label);
		return -ENOTSUP;
	}
	if (param->fp_obd_uuid != NULL && is_mdt) {
		llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ENOTSUP,
			    "--ost needs an OST; over '%s' it would ask which OSTs a file is striped over, which this search does not answer",
			    tgt->tt_label);
		return -ENOTSUP;
	}

	if (param->fp_mdt_uuid != NULL) {
		indexes =''', 'targets mdt')
    s = rep(s, '''	if (param->fp_obd_uuid != NULL) {
		if (is_mdt) {
			llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO,
				    -ENOTSUP,
				    "--ost needs an OST; over '%s' it would ask which OSTs a file is striped over, which this search does not answer",
				    tgt->tt_label);
			return -ENOTSUP;
		}

		for''', '''	if (param->fp_obd_uuid != NULL) {
		for''', 'targets ost')
    return s


CALLER = re.compile(r'''	/\*
	 \* --ost and --mdt are about the target, so the label has to be read
	 \* before the search can say whether they can be answered\.  The probe
	 \* is an open and a close, paid only when one of the two was given\.
	 \*/
	if \(param->fp_obd_uuid != NULL \|\| param->fp_mdt_uuid != NULL\) \{
		rc = scan_device_target\((?P<args>[^)]*)\);
		if \(rc == 0\) \{
			probed = true;
			rc = find_device_targets\(param, &tgt\);
		\}
		if \(rc != 0\)
			goto out;
(?P<mdtidx>		/\*
		 \* Every object an MDT scan delivers.*?
		if \(param->fp_mdt_uuid != NULL\)
			param->fp_file_mdt_index = \(int\)tgt\.tt_index;
)	\}

	/\*
	 \* An OST object has no layout, so these would be compared against a
	 \* default that was never read\.  A failed probe has already said why,
	 \* and the scan would fail the same way and say it twice\.
	 \*/
	if \(find_asks_layout\(param\)\) \{
		if \(!probed\) \{
			rc = scan_device_target\((?P=args)\);
			if \(rc != 0\)
				goto out;
		\}
		if \(tgt\.tt_flags & LLAPI_SCAN_TGT_OST\) \{
			llapi_error\(LLAPI_MSG_ERROR \| LLAPI_MSG_NO_ERRNO,
				    -ENOTSUP,
				    "the layout options need an MDT; '%s' is an OST, whose objects carry no layout",
				    tgt\.tt_label\);
			rc = -ENOTSUP;
			goto out;
		\}
	\}
''', re.S)


def e_caller(s):
    m = CALLER.search(s)
    if not m or len(CALLER.findall(s)) != 1:
        raise RuntimeError('caller block')
    new = '''	/*
	 * --ost, --mdt and the layout options are about the target, so the
	 * label has to be read before the search can say whether they can be
	 * answered.  The probe is an open and a close, paid only when one of
	 * them was given.
	 */
	if (param->fp_obd_uuid != NULL || param->fp_mdt_uuid != NULL ||
	    find_asks_layout(param)) {
		rc = scan_device_target(%s);
		if (rc != 0)
			goto out;
	}

	/*
	 * An OST object has no layout, so these would be compared against a
	 * default that was never read.  Checked before find_device_targets()
	 * can skip this device, so every device of a sweep refuses it.
	 */
	if (find_asks_layout(param) && (tgt.tt_flags & LLAPI_SCAN_TGT_OST)) {
		llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ENOTSUP,
			    "the layout options need an MDT; '%%s' is an OST, whose objects carry no layout",
			    tgt.tt_label);
		rc = -ENOTSUP;
		goto out;
	}

	if (param->fp_obd_uuid != NULL || param->fp_mdt_uuid != NULL) {
		rc = find_device_targets(param, &tgt);
		if (rc != 0)
			goto out;
%s	}
''' % (m.group('args'), m.group('mdtidx'))
    s = s[:m.start()] + new + s[m.end():]
    return rep(s, '\tbool probed = false;\n', '', 'probed')


# ---- 68415 -------------------------------------------------------------
def e_accept(s):
    s = rep(s, " * file's size when the request names a size, blocks or an mtime, as stat(2)\n",
            " * file's size when the request names a size, blocks or a time, as stat(2)\n", 'glimpse')
    s = rep(s, "\t\t\tsl->sl_accepted = o->co_index;\n\t\t\treturn 0;\n",
            "\t\t\tscan_cl_accept(sl, o->co_index);\n\t\t\treturn 0;\n", 'acc1')
    s = rep(s, "\t\tsl->sl_accepted = o->co_index;\n\t\treturn 0;\n\t}\n\n\tif (sc->sc_flags & LLAPI_SCAN_CL_F_RESOLVE)",
            "\t\tscan_cl_accept(sl, o->co_index);\n\t\treturn 0;\n\t}\n\n\tif (sc->sc_flags & LLAPI_SCAN_CL_F_RESOLVE)", 'acc2')
    s = rep(s, "\tsl->sl_accepted = o->co_index;\n\n\treturn 0;\n}\n",
            "\tscan_cl_accept(sl, o->co_index);\n\n\treturn 0;\n}\n", 'acc3')
    s = rep(s, '''/*
 * @keyed says the object came out of the coalescing cache''', '''/*
 * Raised, never lowered: a held object flushed after a later one was
 * delivered has a lower index, and lowering would stop _CLEAR short.
 */
static void scan_cl_accept(struct scan_cl *sl, __u64 index)
{
	if (index > sl->sl_accepted)
		sl->sl_accepted = index;
}

/*
 * @keyed says the object came out of the coalescing cache''', 'helper')
    return s


# ---- 68416 -------------------------------------------------------------
def e_scan(s):
    s = rep(s, '''	 * swapped in on the path, or a mount over a directory -- and that is
	 * not the object asked for either.
	 */''', '''	 * swapped in on the path, or a mount over a directory -- and that is
	 * not the object asked for either.  Client modules with only the V1
	 * getinfo ioctl return no FID, so every lookup is -ESTALE there.
	 */''', 'v1')
    return rep(s, '''	/*
	 * fid2path answers relative to the filesystem root, and "/" for the
	 * root itself, which would compose''', '''	/*
	 * fid2path answers relative to the mount root, and "/" for the
	 * root itself, which would compose''', 'mount root')


def e_fidman(s):
    s = rep(s, "answers relative to the filesystem root and a caller needs the whole name. A\n",
            "answers relative to the mount root and a caller needs the whole name. A\n", 'man root')
    return rep(s, '''.B -ESTALE
the name it resolved to holds a different object now.''', '''.B -ESTALE
the name it resolved to holds a different object now, or is no longer on
Lustre. Client modules with only the V1 getinfo ioctl return no FID, so
every lookup answers this there.''', 'man estale')


# ---- 68417 -------------------------------------------------------------
SEEN_FNS = '''static int find_fid_cmp(const void *a, const void *b)
{
	const struct lu_fid *x = a, *y = b;

	if (x->f_seq != y->f_seq)
		return x->f_seq < y->f_seq ? -1 : 1;
	if (x->f_oid != y->f_oid)
		return x->f_oid < y->f_oid ? -1 : 1;
	if (x->f_ver != y->f_ver)
		return x->f_ver < y->f_ver ? -1 : 1;
	return 0;
}

/*
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

'''


def e_since(s):
    s = rep(s, '#include <pwd.h>\n', '#include <pwd.h>\n#include <search.h>\n', 'include')
    i = s.index('struct find_since_state {')
    j = s.index('\n};\n', i)
    s = s[:j] + '''
	/* FIDs already taken, across MDTs: _ONCE's set is per MDT */
	void			*fss_seen;
	bool			 fss_multi_mdt;''' + s[j:]
    s = rep(s, '/* One coalesced object out of an MDT\'s changelog. */\nstatic int find_since_cand_cb(',
            SEEN_FNS + '/* One coalesced object out of an MDT\'s changelog. */\nstatic int find_since_cand_cb(', 'fns')
    s = rep(s, '''	/* the window cut is find_since_filter_cb()'s, before this */
	st->fss_cand++;
''', '''	if (st->fss_multi_mdt) {
		rc = find_since_seen(st, &rec->lfsr_fid);
		if (rc != 0)
			return rc < 0 ? rc : 0;
	}

	/* the window cut is find_since_filter_cb()'s, before this */
	st->fss_cand++;
''', 'dedup')
    loop = '''	for (i = 0; i < mdt_count; i++) {
		struct llapi_scan_changelog_param sc = { 0 };
'''
    s = rep(s, loop, '\tst.fss_multi_mdt = mdt_count > 1;\n' + loop, 'multi')
    k = s.index('\tst.fss_multi_mdt = mdt_count > 1;\n')
    o = s.index('out:\n\tfree(mdts);\n', k)
    s = s[:o] + 'out:\n\ttdestroy(st.fss_seen, free);\n' + s[o + 5:]
    return rep(s, '''	{
		struct lu_fid mfid;

		st.fss_fileset = llapi_path2fid(mnt_path, &mfid) == 0 &&
				 !lu_fid_eq(&mfid, &LU_ROOT_FID);
	}
''', '\tst.fss_fileset = find_mount_is_fileset(mnt_path) == 1;\n', 'fileset')


# ---- 68418 -------------------------------------------------------------
def e_changelog(s):
    s = rep(s, '\tif (st->fss_multi_mdt) {\n',
            '\tif (st->fss_multi_mdt && !st->fss_as_recorded) {\n', 'as_recorded')
    s = rep(s, '''	if (st.fss_unresolved != 0)
		llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
			    "%llu objects have no pathname and are named by FID",
			    (unsigned long long)st.fss_unresolved);''', '''	/* --changelog reads the whole filesystem's log, fileset or not */
	if (st.fss_unresolved != 0)
		llapi_error(LLAPI_MSG_WARN | LLAPI_MSG_NO_ERRNO, 0,
			    "%llu objects have no pathname%s and are named by FID",
			    (unsigned long long)st.fss_unresolved,
			    st.fss_fileset && st.fss_as_recorded ?
			    " or are outside this fileset" : "");''', 'unresolved')
    return rep(s, '''	if (param->fp_max_depth != (unsigned int)-1 ||
	    param->fp_min_depth != 0) {
		llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ENOTSUP,
			    "--maxdepth and --mindepth describe a walk''', '''	/* 0 too, as find_device_supported(): llapi_find_param_alloc() */
	if ((param->fp_max_depth != (unsigned int)-1 &&
	     param->fp_max_depth != 0) || param->fp_min_depth != 0) {
		llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ENOTSUP,
			    "--maxdepth and --mindepth describe a walk''', 'depth')


def e_sinceman(s):
    first = '''.TP 15
.B -ENOTSUP
.I fp_thread_count
is above 1. This source is single-threaded, and the count is tested as soon
as the arguments are well formed \\(em before
.I path
is resolved or any MDT is read \\(em so a
.B find_param
that a walk left a thread count in is refused rather than run on one thread.
'''
    s = rep(s, first, '', 'enotsup1')
    old = '''Refused before the search runs rather than answered from a record that
cannot settle it.
'''
    return rep(s, old, old + '''The predicates are named by their
.BR lfs-find (1)
options; each is a
.B find_param
field. Also
.I fp_thread_count
above 1. This source is single-threaded, and the count is tested as soon
as the arguments are well formed \\(em before
.I path
is resolved or any MDT is read \\(em so a
.B find_param
that a walk left a thread count in is refused rather than run on one thread.
''', 'enotsup2')


# ---- 68419 -------------------------------------------------------------
def e_cookie(s):
    s = rep(s, '''			 * by running the command twice.  A cookie written
			 * before this carried no root and is accepted.
''', '''			 * by running the command twice.  A header with no
			 * root is refused the same way: find_cookie_write()
			 * always writes one.
''', 'noroot comment')
    s = rep(s, '''			if (oldroot != NULL &&
			    (oldlen != strlen(rootesc) ||
			     strncmp(oldroot, rootesc, oldlen) != 0)) {''', '''			if (oldroot == NULL) {
				llapi_error(LLAPI_MSG_ERROR |
					    LLAPI_MSG_NO_ERRNO, -EINVAL,
					    "'%s' names no search root in its header",
					    file);
				fclose(fp);
				return -EINVAL;
			}
			if (oldlen != strlen(rootesc) ||
			    strncmp(oldroot, rootesc, oldlen) != 0) {''', 'noroot')
    return rep(s, '''		 * which is the failure the stale check exists to catch.  The
		 * span also refuses the sign %x would otherwise take:
		 * "-MDT-1" read back as 0xffffffff, an out-of-bounds write
		 * rather than an anchor to ignore.
''', '''		 * which is the failure the stale check exists to catch.  The
		 * span also refuses a sign, which %x would take.
''', 'sign')


RACE = '''Nor is one record lost to a race in the MDT: records are written
in parallel, so a run that reaches the end of a busy log can read record N+1
before N is complete, and the next run starts past N. Keep
.I FILE
outside the searched tree; the run writes it, so inside the tree it reports
itself on every run. '''


def e_findman(s):
    if 'not caught. To accept' not in s:
        return rep(s, 'refused instead. To accept',
                   'refused instead. ' + RACE + 'To accept', 'findman 68419')
    return rep(s, '''so a purge that reaches a later MDT while an earlier one is being read is
not caught. To accept''', '''so a purge that reaches a later MDT while an earlier one is being read is
not caught. Nor is one record lost to a race in the MDT: records are written
in parallel, so a run that reaches the end of a busy log can read record N+1
before N is complete, and the next run starts past N. Keep
.I FILE
outside the searched tree; the run writes it, so inside the tree it reports
itself on every run. To accept''', 'findman')


# ---- 68420 -------------------------------------------------------------
def e_test(s):
    return rep(s, '''	# A line the cookie is never written with.  "%x" takes a sign, so a
	# negative MDT index read back as an unsigned one is a write past the
	# end of the anchor array rather than an anchor to ignore: this run
	# either ignores the line or dies.
	stack_trap "rm -f $ck.bad $ck.other"
	cat > $ck.bad <<-EOF
		# lfs find --since-cookie for $FSNAME
		$FSNAME-MDT-1 42
		$FSNAME-MDT-800 42
	EOF
	$LFS find $DIR/$tdir --since-cookie $ck.bad -type f > /dev/null ||
		error "a negative MDT index should be ignored"
''', '''	# Lines the cookie is never written with: a malformed MDT name is
	# ignored, not read as an anchor.
	stack_trap "rm -f $ck.bad $ck.other $ck.noroot"
	{ head -n 1 $ck; echo "$FSNAME-MDT-1 42"; echo "$FSNAME-MDT-800 42"; } \\
		> $ck.bad
	$LFS find $DIR/$tdir --since-cookie $ck.bad -type f > /dev/null ||
		error "a malformed MDT name should be ignored"

	# the run always writes its root, so a header without one is refused
	cat > $ck.noroot <<-EOF
		# lfs find --since-cookie for $FSNAME
		$FSNAME-MDT0000 1
	EOF
	$LFS find $DIR/$tdir --since-cookie $ck.noroot -type f &> /dev/null &&
		error "a cookie with no root should be refused"
''', 'test')


# (owning commit index, file, edit)
EDITS = [
    (3, PF, e_targets), (3, PF, e_caller),
    (7, CL, e_accept),
    (8, SC, e_scan), (8, 'Documentation/man3/llapi_scan_fid.3', e_fidman),
    (9, PF, e_since),
    (10, PF, e_changelog),
    (10, 'Documentation/man3/llapi_find_since.3', e_sinceman),
    (11, PF, e_cookie), (11, 'Documentation/man1/lfs-find.1', e_findman),
    (12, 'lustre/tests/sanity.sh', e_test),
]

def wsub(msg, old, new, what):
    pat = r'\s+'.join(re.escape(w) for w in old.split())
    m, n = re.subn(pat, lambda _: new, msg)
    if n != 1:
        raise RuntimeError('%s: %d matches' % (what, n))
    return m


def refill(text, width=72):
    import textwrap
    return textwrap.fill(text, width)


def m_68415(msg):
    msg = wsub(msg, "blocks or mtime was asked for;", "blocks or a time was asked for;", 'm1')
    return wsub(msg, "A regular file's size and mtime are strict only when the OSTs were glimpsed, "
                "which happens when the demand mask is 0 or names a size, blocks or an mtime. "
                "Otherwise the size is the MDT's lazy one, which LLAPI_SCAN_LAZY_SIZE and "
                "LLAPI_SCAN_LAZY_BLOCKS say, and the mtime is left out.",
                refill("A regular file's size and times are strict only when the OSTs were "
                       "glimpsed, which happens when the demand mask is 0 or names a size, "
                       "blocks or a time. Otherwise the size is the MDT's lazy one, which "
                       "LLAPI_SCAN_LAZY_SIZE and LLAPI_SCAN_LAZY_BLOCKS say, and the times "
                       "are left out."), 'm2')


def m_68420(msg):
    return wsub(msg, "160Ac also feeds the cookie two files it is never written with: one "
                "whose MDT index is negative, and one whose header names another filesystem. "
                "Neither is a bad anchor to ignore -- the first indexes the anchor array far "
                "past its end, and the second is a whole-log rescan of this filesystem plus "
                "the loss of the other one's anchors -- so one has to be ignored and the "
                "other refused, and the file it refuses has to still be there afterwards.",
                refill("160Ac also feeds the cookie three files it is never written with. "
                       "One has a malformed MDT name, which is ignored. One names another "
                       "filesystem in its header; read, it would rescan this filesystem's "
                       "whole log and drop the other one's anchors, so it is refused, and "
                       "the file has to still be there afterwards. One has no search root "
                       "in its header, and is refused too."), 'm3')


MSG = {7: m_68415, 12: m_68420}


def build(dry):
    parent = git('rev-parse', BASE).decode().strip()
    fail = False
    for i, c in enumerate(STACK):
        files = {}
        for (own, f, fn) in EDITS:
            if own > i:
                continue
            if f not in files:
                files[f] = git('show', '%s:%s' % (c, f)).decode()
            try:
                files[f] = fn(files[f])
            except Exception as e:
                print('commit %d %s: %s %s: %s' % (i, c, f, fn.__name__, e))
                fail = True
        if not dry and not files and i not in MSG and \
                git('rev-parse', c + '^').decode().strip() == parent:
            parent = git('rev-parse', c).decode().strip()
            print(i, c, 'kept')
            continue
        if dry:
            if i in MSG:
                try:
                    MSG[i](git('log', '-1', '--format=%B', c).decode())
                except Exception as e:
                    print('msg %d: %s' % (i, e)); fail = True
            continue
        # tree: original tree with the edited blobs
        env_idx = '/tmp/rb-index'
        subprocess.run(['rm', '-f', env_idx])
        envp = dict(__import__('os').environ, GIT_INDEX_FILE=env_idx)
        subprocess.run(['git', '-C', REPO, 'read-tree', c], env=envp, check=True)
        for f, txt in files.items():
            mode = git('ls-tree', c, f).decode().split()[0]
            blob = git('hash-object', '-w', '--stdin', inp=txt.encode()).decode().strip()
            subprocess.run(['git', '-C', REPO, 'update-index', '--cacheinfo',
                            '%s,%s,%s' % (mode, blob, f)], env=envp, check=True)
        tree = subprocess.run(['git', '-C', REPO, 'write-tree'], env=envp,
                              capture_output=True, check=True).stdout.decode().strip()
        msg = git('log', '-1', '--format=%B', c).decode().rstrip('\n') + '\n'
        if i in MSG:
            msg = MSG[i](msg)
        fmt = lambda k: git('log', '-1', '--format=' + k, c).decode().strip()
        env2 = dict(__import__('os').environ,
                    GIT_AUTHOR_NAME=fmt('%an'), GIT_AUTHOR_EMAIL=fmt('%ae'),
                    GIT_AUTHOR_DATE=fmt('%ad'))
        parent = subprocess.run(['git', '-C', REPO, 'commit-tree', tree, '-p', parent],
                                input=msg.encode(), env=env2, capture_output=True,
                                check=True).stdout.decode().strip()
        print(i, c, '->', parent[:10])
    return fail, parent


if __name__ == '__main__':
    dry = len(sys.argv) > 1 and sys.argv[1] == 'dry'
    fail, tip = build(dry)
    if fail:
        sys.exit(1)
    if not dry:
        print('TIP', tip)
