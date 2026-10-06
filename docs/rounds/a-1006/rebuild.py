#!/usr/bin/env python3
# Rebuild fix-1006: the AI-round edits (proven at the fixup tip 8506d66293)
# applied to each commit's own tree from the commit that owns each edit
# upward.  Idempotent per edit: new text present -> skip.  No cherry-picks.
import os, subprocess, sys

REPO = '/home/nishida/lfs-fix-1006'
BASE = '507b70072f^'
STACK = ['507b70072f', '5eadb15998', 'c9c29b8112', 'e6cc02b153',
         '4fb131b82f', '0e8a719ed2', '75f8b473d0', '0e2194257c',
         '85b616af4f', '88a8ba3435', 'f8691197ca', '839988686f',
         '3a179e7307']
C157, C159, C163, C415, C417, C418, C419, C420 = 1, 3, 5, 7, 9, 10, 11, 12
PF = 'lustre/utils/liblustreapi_pfind.c'


def git(*a, inp=None):
    return subprocess.run(['git', '-C', REPO] + list(a), input=inp,
                          capture_output=True, check=True).stdout


def rep(s, old, new, what):
    if new in s:
        return s
    n = s.count(old)
    if n != 1:
        raise RuntimeError('%s: %d matches' % (what, n))
    return s.replace(old, new)


EDITS = []


def edit(own, f, old, new, what, until=None):
    EDITS.append((own, f, old, new, what, until))


# ---- 68157: find_decide()'s return ------------------------------------
edit(C157, PF, ''' * and no caller has ever read it.  A positive would collide with the 1
 * cb_find_init() returns for "do not descend", which is the value this
 * lands in there.
 */''', ''' * and no caller has ever read it.  No positive: cb_find_init() acts only
 * on a negative and then sets its own return, so a positive would be lost.
 */''', '157 ret')

# ---- 68159: ! --projid, and the LINKEA bit ----------------------------
edit(C159, PF, '''			 * not reach i_projid genuinely has none of.  Neither a
			 * match nor a miss, as an unglimpsable size is.
			 */''', '''			 * not reach i_projid genuinely has none of.  Neither a
			 * match nor a miss, as an unglimpsable size is.  This
			 * holds for ! --projid N too, unlike ! -btime: a walk
			 * is told the kernel's default of 0 for such an inode,
			 * so ! --projid 0 would not match it there.
			 */''', '159 projid')
edit(C159, 'Documentation/man3/llapi_scan_device.3', '''.I lfsr_linkeasize
bytes at it.
.TP
.I lfsr_parent_fid''', '''.I lfsr_linkeasize
bytes at it. The bit is set only when the first entry parses, so a
.B trusted.link
that is damaged there is not delivered at all.
.I lfsr_name
can still be NULL with the bit set, when that entry's name is empty.
.TP
.I lfsr_parent_fid''', '159 man3')

# ---- 68163: ZFS 2.4's /boot/zfs/zpool.cache ---------------------------
edit(C163, 'lustre/utils/libscan_zfs.c', '''		zfs_arc_max = 256ULL << 20;
		kernel_init(SPA_MODE_READ);
	}''', '''		zfs_arc_max = 256ULL << 20;
		kernel_init(SPA_MODE_READ);
		/*
		 * ZFS 2.4 also reads /boot/zfs/zpool.cache when that open
		 * fails.  Nothing is imported yet: drop whatever it loaded.
		 */
		spa_evict_all();
	}''', '163 evict')

# ---- 68415: 56Eea keeps the subdirectories on MDT0 --------------------
edit(C415, 'lustre/tests/sanity.sh', '''	# log full of somebody else's records.  Made here rather than left to
	# the binary, which can only notice and refuse.
	rm -rf $dir
	$LFS mkdir -i 0 $dir || error "mkdir $dir failed"
''', '''	# log full of somebody else's records.  Made here rather than left to
	# the binary, which can only notice and refuse.  The default layout
	# keeps its subdirectories there too, which ROOT's space-balanced
	# default would otherwise move once the MDTs drift apart.
	rm -rf $dir
	$LFS mkdir -i 0 $dir || error "mkdir $dir failed"
	$LFS setdirstripe -D -i 0 -c 1 $dir ||
		error "setdirstripe -D $dir failed"
''', '415 sanity')
edit(C415, 'lustre/tests/llapi_scan_changelog_test.c', '''	 * Changelog user -- sanity 56Eea creates it with "lfs mkdir -i 0",
	 * before registering, to put it on the MDT whose log is read -- and''',
     '''	 * Changelog user -- sanity 56Eea creates it with "lfs mkdir -i 0"
	 * and a default layout on MDT0, before registering, so that this and
	 * every directory below it are on the MDT whose log is read -- and''',
     '415 test.c')

# ---- 68417: --mdt under --since, and a sign after white space ---------
edit(C417, PF, '''	isdir = (rec->lfsr_stx.stx_mask & STATX_MODE) &&
		S_ISDIR(rec->lfsr_stx.stx_mode);
	param->fp_get_lmv = isdir && find_needs_lmv(param);

	/*
	 * The path-ful form, unlike a target scan's''', '''	isdir = (rec->lfsr_stx.stx_mask & STATX_MODE) &&
		S_ISDIR(rec->lfsr_stx.stx_mode);
	param->fp_get_lmv = isdir && find_needs_lmv(param);

	/* check_mdt_match() reads this; llapi_scan_fid() set its own copy */
	param->fp_file_mdt_index = (rec->lfsr_valid & LLAPI_SCAN_MDT_INDEX) ?
				   (int)rec->lfsr_mdt_index : OBD_NOT_FOUND;
	/* as the walk does: --mdt cannot be answered without the index */
	if (param->fp_mdt_uuid != NULL &&
	    param->fp_file_mdt_index == OBD_NOT_FOUND)
		return 0;

	/*
	 * The path-ful form, unlike a target scan's''', '417 mdt')
edit(C418, PF, '''	 * LLAPI_SCAN_MDT_INDEX rides along because find_want() adds it with
	 * the rest; nothing on this path reads it.
	 */''', '''	 * LLAPI_SCAN_MDT_INDEX is there for --mdt, which find_since_rec_cb()
	 * copies into fp_file_mdt_index.
	 */''', '418 want')
edit(C417, 'lustre/utils/lfs_find_parse.c', '''	/*
	 * strtoull() accepts a leading sign and wraps it, so "-5" would come
	 * back as an index near 2^64 rather than as the mistake it is.
	 * Neither an index nor a duration is ever signed here.
	 */
	if (*str == '-' || *str == '+')
		goto bad;
''', '''	/*
	 * strtoull() skips white space and then wraps a sign, so " -5" would
	 * come back as an index near 2^64.  Only a leading digit is a number
	 * here; anything else is for the timestamp formats.
	 */
	if (!isdigit((unsigned char)*str))
		goto timestamp;
''', '417 sign')
edit(C417, 'lustre/utils/lfs_find_parse.c', '''	/* a timestamp, or @<epoch second> */
	for (i = 0; fmts[i] != NULL; i++) {''', '''timestamp:
	/* a timestamp, or @<epoch second> */
	for (i = 0; fmts[i] != NULL; i++) {''', '417 label')

edit(C417, PF, ''' * It is asked here rather than in the callback because sc_filter sees every
 * record the stream produced, in order and before any lookup, and the
 * callback does not: under LLAPI_SCAN_CL_F_ONCE an object already delivered
 * is dropped before the callback.
 */''', ''' * It is asked here rather than in the callback because sc_filter sees each
 * delivery before any lookup, and the callback does not: under
 * LLAPI_SCAN_CL_F_ONCE an object already delivered is dropped before the
 * callback.
 */''', '417 filter', until=C419)
edit(C419, PF, ''' * Both are here rather than in the callback because sc_filter sees every
 * record the stream produced, in order and before any lookup, and the
 * callback does not.  A record about no object, such as a CL_MARK, is''',
     ''' * Both are here rather than in the callback because sc_filter sees each
 * delivery before any lookup, and the callback does not.  A record about
 * no object, such as a CL_MARK, is''', '419 filter')

# ---- 68419: the anchor under coalescing (owed from 10-05) -------------
edit(C419, PF, '''	 * records the callback does not see the scan finished on, and the
	 * next run re-read them to report them again.
	 */''', '''	 * records the callback does not see the scan finished on, and the
	 * next run re-read them to report them again.  Coalesced, a record
	 * carries its object's latest index and can arrive after a higher
	 * one, so only the highest is kept.
	 */''', '419 anchor')

# ---- 68418: --maxdepth 0, and one line per log ------------------------
edit(C418, 'lustre/utils/lfs.c', '''
	do {
		if (param->fp_since_kind != LLAPI_SINCE_NONE ||
''', '''
	/*
	 * Here, not in the library: lfs seeds fp_max_depth with -1, so 0 is
	 * the user's, while llapi_find_param_alloc() gives an API caller 0.
	 */
	if (param->fp_changelog_mdt != NULL &&
	    (param->fp_max_depth != (unsigned int)-1 ||
	     param->fp_min_depth != 0)) {
		fprintf(stderr,
			"error: %s: --maxdepth and --mindepth describe a walk, which --changelog is not; --since honours them\\n",
			argv[0]);
		ret = -ENOTSUP;
		goto err;
	}

	do {
		if (param->fp_since_kind != LLAPI_SINCE_NONE ||
''', '418 lfs')
edit(C418, PF, '''	for (p = path + rootlen; *p != '\\0'; p++)
		if (*p == '/' && *(p + 1) != '\\0')
			depth++;

	if (param->fp_max_depth''', '''	/* refused under --changelog, where 0 is an API caller's unset */
	if (st->fss_as_recorded)
		return true;

	for (p = path + rootlen; *p != '\\0'; p++)
		if (*p == '/' && *(p + 1) != '\\0')
			depth++;

	if (param->fp_max_depth''', '418 under')
edit(C418, 'Documentation/man1/lfs-find.1', '''a second burst is a second event.
.B --since
asks what is true now and prints such an object once.''', '''a second burst is a second event.
Under
.BR "--changelog all" ,
an object recorded in more than one MDT's log \\(em a remote directory, or a
file renamed from one MDT to another \\(em is printed once for each log.
.B --since
asks what is true now and prints such an object once.''', '418 man')

# ---- 68420: a plain --since example -----------------------------------
edit(C420, 'Documentation/man1/lfs-find.1', '''.PP
List what changed anywhere in the filesystem in the last hour, as the
changelog recorded it:''', '''.PP
List the regular files that changed in the last two hours, each one checked
against the live filesystem:
.EX
.RS
.B # lfs find /mnt/lustre --since 2h -type f
.RE
.EE
.PP
List what changed anywhere in the filesystem in the last hour, as the
changelog recorded it:''', '420 example')


# ---- commit messages --------------------------------------------------
def m_159(m):
    return rep(m, '''A field that the inode format has no room for, such as a project id or
a birth time, is counted as undecided and reported at the end.
''', '''A field that the inode format has no room for, such as a project id or
a birth time, is counted as undecided and reported at the end. The
negations differ: a walk sees no birth time for such an inode either,
so ! -btime matches it, but a walk is told a project id of 0, so
! --projid N stays undecided.
''', 'm159')


def m_163(m):
    return rep(m, '''of /dev. The scan loads no /etc/zfs/zpool.cache: a pool listed there
would be opened directly, before those checks, and a pool the kernel
holds would answer EREMOTEIO instead of EBUSY.
''', '''of /dev. The scan loads no /etc/zfs/zpool.cache: a pool listed there
would be opened directly, before those checks, and a pool the kernel
holds would answer EREMOTEIO instead of EBUSY. ZFS 2.4 also falls back
to /boot/zfs/zpool.cache, so the scan drops every pool that
kernel_init() loaded before it opens its own.
''', 'm163')


def m_417(m):
    m = rep(m, '''LU-20650 lfs: find --since, from the changelog

The three pieces''', '''LU-20650 lfs: add find --since, from the changelog

Add "lfs find --since TIME|INDEX" and llapi_find_since(). They run
find's predicates only over the objects that an MDT changelog reports
as changed, so a periodic search does not have to walk the whole
namespace.

The three pieces''', 'm417 open')
    m = rep(m, '''spellings.  A leading sign is refused rather than wrapped through
strtoull(), and a duration reaching past the epoch is a typo rather
than a window.
''', '''spellings.  Only a value that starts with a digit is read as a
number, so a sign is refused, even after a space, rather than wrapped
through strtoull().  A duration reaching past the epoch is a typo
rather than a window.
''', 'm417 sign')
    m = rep(m, '''--maxdepth and --mindepth.  Without that, a find rooted at one
directory would answer for its siblings.
''', '''--maxdepth and --mindepth.  Without that, a find rooted at one
directory would answer for its siblings.  --mdt is answered from the
index in the record: llapi_scan_fid() fills its own find_param, so
the index is copied into the caller's for check_mdt_match().
''', 'm417 mdt')
    return m


def m_418(m):
    m = rep(m, '''--mindepth are refused at every setting -- they describe a walk, or
need something a per-MDT log does not have.''', '''--mindepth are refused at every setting -- they describe a walk, or
need something a per-MDT log does not have.  lfs refuses an explicit
--maxdepth 0 as well.  The library cannot, because
llapi_find_param_alloc() gives an API caller 0, so it ignores the
depth bounds under --changelog.''', 'm418 depth')
    m = rep(m, '''sr_fd is not always -1 for a regular file''',
            '''lfsr_fd is not always -1 for a regular file''', 'm418 fd1')
    m = rep(m, '''leaves that descriptor in sr_fd.''',
            '''leaves that descriptor in lfsr_fd.''', 'm418 fd2')
    return m


def m_415(m):
    return rep(m, '''guarantee, so the test makes the directory on MDT0 itself; the binary
still checks and refuses.  -u passes a registered Changelog user.
''', '''guarantee, so the test makes the directory on MDT0 itself, with a
default layout that keeps the binary's own subdirectories there too;
the binary still checks and refuses.  -u passes a registered
Changelog user.
''', 'm415')


def m_420(m):
    return rep(m, '''later MDT during it is not caught.
''', '''later MDT during it is not caught.  EXAMPLES gains a plain --since
search.
''', 'm420')


MSG = {C159: m_159, C163: m_163, C415: m_415, C417: m_417, C418: m_418,
       C420: m_420}


def build(dry):
    parent = git('rev-parse', BASE).decode().strip()
    fail = False
    for i, c in enumerate(STACK):
        files = {}
        for (own, f, old, new, what, until) in EDITS:
            if own > i or (until is not None and i >= until):
                continue
            if f not in files:
                files[f] = git('show', '%s:%s' % (c, f)).decode()
            try:
                files[f] = rep(files[f], old, new, what)
            except Exception as e:
                print('commit %d %s: %s' % (i, c, e))
                fail = True
        msg = git('log', '-1', '--format=%B', c).decode().rstrip('\n') + '\n'
        if i in MSG:
            try:
                msg = MSG[i](msg)
            except Exception as e:
                print('msg %d: %s' % (i, e))
                fail = True
        if dry:
            continue
        orig = git('log', '-1', '--format=%B', c).decode().rstrip('\n') + '\n'
        same = all(git('show', '%s:%s' % (c, f)).decode() == t
                   for f, t in files.items())
        if same and msg == orig and \
                git('rev-parse', c + '^').decode().strip() == parent:
            parent = git('rev-parse', c).decode().strip()
            print(i, c, 'kept')
            continue
        idx = '/tmp/claude-1004/rb1006-index'
        subprocess.run(['rm', '-f', idx])
        envp = dict(os.environ, GIT_INDEX_FILE=idx)
        subprocess.run(['git', '-C', REPO, 'read-tree', c], env=envp,
                       check=True)
        for f, txt in files.items():
            mode = git('ls-tree', c, f).decode().split()[0]
            blob = git('hash-object', '-w', '--stdin',
                       inp=txt.encode()).decode().strip()
            subprocess.run(['git', '-C', REPO, 'update-index', '--cacheinfo',
                            '%s,%s,%s' % (mode, blob, f)], env=envp,
                           check=True)
        tree = subprocess.run(['git', '-C', REPO, 'write-tree'], env=envp,
                              capture_output=True,
                              check=True).stdout.decode().strip()
        fmt = lambda k: git('log', '-1', '--format=' + k, c).decode().strip()
        env2 = dict(os.environ, GIT_AUTHOR_NAME=fmt('%an'),
                    GIT_AUTHOR_EMAIL=fmt('%ae'), GIT_AUTHOR_DATE=fmt('%ad'))
        parent = subprocess.run(['git', '-C', REPO, 'commit-tree', tree,
                                 '-p', parent], input=msg.encode(), env=env2,
                                capture_output=True,
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
