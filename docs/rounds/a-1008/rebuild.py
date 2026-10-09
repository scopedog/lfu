#!/usr/bin/env python3
# Rebuild fix-1008: the 10-08 AI-round edits (on PS of 10-07, a1007-pushed)
# applied to each commit's own tree from the commit that owns each edit
# upward.  Idempotent per edit: new text present -> skip.  No cherry-picks.
# Framework copied from ../a-1007/rebuild.py.
import os, re, subprocess, sys

REPO = '/home/nishida/lfs-fix-1007'
BASE = '507b70072f^'
# 68156 .. 68420, 69443, then 69500 69501 69502 69503
STACK = ['507b70072f', '41ce6d4dd3', '9b2b5a3e00', '05f759fd87',
         '31e7e4514b', '37b7eea72b', '9c978aa1c1', '1e2c28137b',
         'd5da1d2821', '1ce5c85105', '042fdbdcc3', '32eed0704f',
         '77d69359a6', '37e8b4ce9a', '5fb491bd27', 'f3f607be9a',
         '4f3960ebaf', 'ab63954c73']
(C156, C157, C158, C159, C160, C163, C288, C415, C416, C417, C418, C419,
 C420, C443, F_GAP, F_NLINK, F_PICK, F_ZFS) = range(18)
PF = 'lustre/utils/liblustreapi_pfind.c'
LA = 'lustre/utils/liblustreapi.c'
LI = 'lustre/utils/lustreapi_internal.h'
ZF = 'lustre/utils/libscan_zfs.c'
SC = 'lustre/utils/liblustreapi_scan_changelog.c'
LF1 = 'Documentation/man1/lfs-find.1'
LC3 = 'Documentation/man3/llapi_scan_changelog.3'


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


# ---- 68159: an empty linkea name is damage, not a name -----------------
edit(C159, PF, '''				     &off, name, sizeof(name), NULL) == 0) {
			/*
			 * The linkea claims more names than it can spell:
			 * leh_reccount is capped by the smallest entry that
			 * could fit, so a torn trusted.link parses entry 0
			 * and runs out on a later one.  The names left are''',
     '''				     &off, name, sizeof(name), NULL) == 0 ||
		    name[0] == '\\0') {
			/*
			 * The linkea claims more names than it can spell:
			 * leh_reccount is capped by the smallest entry that
			 * could fit, so a torn trusted.link parses entry 0
			 * and runs out on a later one.  A name that starts
			 * with NUL is the same damage, and fnmatch() would
			 * answer it as "".  The names left are''', '159 empty name')

# ---- 68288: the same, when picking the name to print -------------------
edit(C288, PF, '''				     &named.lfsr_parent_fid) == 0)
			break;
''', '''				     &named.lfsr_parent_fid) == 0)
			break;
		/* an empty name is damage, not a name to place */
		if (name[0] == '\\0')
			continue;
''', '288 empty name')

# ---- 68163: osd_trans_stop() frees it, not the commit callback ---------
edit(C163, ZF, '''	 * and records its id here; the commit callback frees it moments
	 * later, but after a crash nothing has -- osd_unlinked_drain() runs
	 * at the next mount, and a failover partner's copy has not had one.''',
     '''	 * and records its id here; osd_trans_stop() frees it in a new
	 * transaction straight after, but after a crash nothing has --
	 * osd_unlinked_drain() runs at the next mount, and a failover
	 * partner's copy has not had one.''', '163 unlinked free')

# ---- 68415 -------------------------------------------------------------
edit(C415, LC3, '''and the birth time is filled where the MDT has one. No object is opened for read, so resolution adds
no
.B CL_OPEN''', '''and the birth time is filled where the MDT has one.
No object is opened for read, so resolution adds no
.B CL_OPEN''', '415 man wrap')
edit(C415, SC, '''#include <sys/types.h>
#include <time.h>
#include <unistd.h>''', '''#include <sys/types.h>
#include <unistd.h>''', '415 time.h')
edit(C415, SC, '''		/* a lookup is what adds the object's own attributes, and it
		 * needs both the flag and a mount to open through
		 */
		if ((scl.sc_flags & LLAPI_SCAN_CL_F_RESOLVE) &&
		    scl.sc_mnt != NULL)
			known |= SCAN_CL_RESOLVE_MASK;''', '''		/* a lookup adds the object's own attributes; the flag
		 * without a mount was refused above
		 */
		if (scl.sc_flags & LLAPI_SCAN_CL_F_RESOLVE)
			known |= SCAN_CL_RESOLVE_MASK;''', '415 sc_mnt')

# ---- 68417 -------------------------------------------------------------
edit(C417, LF1, '''not when an entry is created, removed or renamed in it, although that changes
its mtime and ctime.
''', '''not when an entry is created, removed or renamed in it, although that changes
its mtime and ctime. A write to a file makes no record until the file is
closed, so a file whose only change is a write by a process that still has it
open, such as the output of a running job, does not appear.
''', '417 man close')

FWC_OLD = '''int llapi_find_with_cb(char *path, struct find_param *param,
		       llapi_find_cb_t cb_init, llapi_find_cb_t cb_fini)
{
	if (param->fp_format_printf_str)'''
FWC = '''int llapi_find_with_cb(char *path, struct find_param *param,
		       llapi_find_cb_t cb_init, llapi_find_cb_t cb_fini)
{
	/* a walk reads no changelog: llapi_find_since() is the call */
	if (%s)
		return -EINVAL;
	if (param->fp_format_printf_str)'''
edit(C417, LA, FWC_OLD,
     FWC % 'param->fp_since_kind != LLAPI_SINCE_NONE',
     '417 find_with_cb', until=C418)
edit(C418, LA, FWC_OLD,
     FWC % '''param->fp_since_kind != LLAPI_SINCE_NONE ||
	    param->fp_changelog_mdt != NULL''',
     '418 find_with_cb', until=C419)
edit(C419, LA, FWC_OLD,
     FWC % '''param->fp_since_kind != LLAPI_SINCE_NONE ||
	    param->fp_changelog_mdt != NULL || param->fp_since_cookie != NULL''',
     '419 find_with_cb')

edit(C417, PF, '''			    "--threads describes a walk; --since reads one changelog per MDT in turn");
		return -ENOTSUP;
	}
''', '''			    "--threads describes a walk; --since reads one changelog per MDT in turn");
		return -ENOTSUP;
	}
	/* warn of a bad -printf directive, as a walk does */
	if (param->fp_format_printf_str)
		validate_printf_str(param);
''', '417 printf', until=C418)
PRINTF = '''			    "--threads describes a walk; %s read one changelog per MDT in turn");
		return -ENOTSUP;
	}
'''
PRINTF_ADD = '''	/* warn of a bad -printf directive, as a walk does */
	if (param->fp_format_printf_str)
		validate_printf_str(param);
'''
edit(C418, PF, PRINTF % '--since and --changelog',
     PRINTF % '--since and --changelog' + PRINTF_ADD, '418 printf',
     until=C419)
edit(C419, PF, PRINTF % '--since, --since-cookie and --changelog',
     PRINTF % '--since, --since-cookie and --changelog' + PRINTF_ADD,
     '419 printf')
edit(C417, PF, '''Give a time (--since 2h, --since @%lld) or name one MDT",
			    (unsigned long long)param->fp_since_index,
			    fsname, mdt_count, (long long)time(NULL));''',
     '''Give a time (--since 2h, --since @1787674596) or name one MDT",
			    (unsigned long long)param->fp_since_index,
			    fsname, mdt_count);''', '417 hint')
edit(C417, PF, 'int common_param_init(struct find_param *param, char *path)',
     'int common_param_init(struct find_param *param, const char *path)',
     '417 cpi def')
edit(C417, LI, 'int common_param_init(struct find_param *param, char *path);',
     'int common_param_init(struct find_param *param, const char *path);',
     '417 cpi decl')
edit(C417, PF, '	rc = common_param_init(param, (char *)path);',
     '	rc = common_param_init(param, path);', '417 cpi cast')

# ---- 69443: no dummy out-pointer ---------------------------------------
edit(C443, PF, ''' * Return: 0, -ESTALE (said here), or the errno reading the log.  @oldest is
 * 0 for an empty log.
 */''', ''' * Return: 0, -ESTALE (said here), or the errno reading the log.  @oldest,
 * if not NULL, is 0 for an empty log.
 */''', '443 doc')
NULL_OLD = '''	int rc;

	*oldest = 0;
	rc = find_cl_first(mdtname, 0, oldest%s);'''
NULL_NEW = '''	__u64 first;
	int rc;

	if (oldest == NULL)
		oldest = &first;
	rc = find_cl_first(mdtname, 0, oldest%s);'''
edit(C443, PF, NULL_OLD % '', NULL_NEW % '', '443 null', until=F_GAP)
edit(F_GAP, PF, NULL_OLD % ', NULL', NULL_NEW % ', NULL', 'gap 443 null')
edit(C443, PF, '''		    starts[mdts[i]] != 0) {
			__u64 oldest;

			rc = find_cookie_purged(mdtname, starts[mdts[i]],
						param->fp_since_cookie,
						&oldest);''', '''		    starts[mdts[i]] != 0) {
			rc = find_cookie_purged(mdtname, starts[mdts[i]],
						param->fp_since_cookie, NULL);''',
     '443 caller')

# ---- 69500: a failed read stops the run; the anchor's second counts ----
edit(F_GAP, PF, '''static void find_since_gap(const struct find_param *param, time_t since,
			   const char *mdtname)
{
	__u64 oldest = 0;
	__s64 when = 0;
	char stamp[32] = "";
	struct tm tm;
	time_t t;
''', '''static int find_since_gap(const struct find_param *param, time_t since,
			  const char *mdtname)
{
	__u64 oldest = 0;
	__s64 when = 0;
	char stamp[32] = "";
	struct tm tm;
	time_t t;
	int rc;
''', 'gap int')
edit(F_GAP, PF, '''	     param->fp_since_kind != LLAPI_SINCE_INDEX))
		return;
	/* an empty log looks the same cleared or idle: nothing to say */
	if (find_cl_first(mdtname, 0, &oldest, &when) < 0 || oldest <= 1)
		return;
''', '''	     param->fp_since_kind != LLAPI_SINCE_INDEX))
		return 0;
	/* an empty log looks the same cleared or idle: nothing to say */
	rc = find_cl_first(mdtname, 0, &oldest, &when);
	if (rc < 0 || oldest <= 1)
		return rc;
''', 'gap rc')
edit(F_GAP, PF, '''				    mdtname, (unsigned long long)oldest);
		return;
	}
''', '''				    mdtname, (unsigned long long)oldest);
		return 0;
	}
''', 'gap index ret')
edit(F_GAP, PF, '''	 * what is known.
	 */
	if (when <= since)
		return;
''', '''	 * what is known.  The window holds the anchor's own second, so a
	 * record from that second may have been cleared too.
	 */
	if (when < since)
		return 0;
''', 'gap boundary')
edit(F_GAP, PF, '''		    "'%s' has been cleared and starts at record %llu, from %s, after the --since anchor; anything cleared after the anchor is not in the answer",
		    mdtname, (unsigned long long)oldest, stamp);
}''', '''		    "'%s' has been cleared and starts at record %llu, from %s, not before the --since anchor; anything cleared from the anchor on is not in the answer",
		    mdtname, (unsigned long long)oldest, stamp);
	return 0;
}''', 'gap msg')
edit(F_GAP, PF, '''		find_since_gap(param, st.fss_since, mdtname);

		rc = llapi_scan_changelog(&sc, find_since_cand_cb, &st);
		if (rc < 0) {''', '''		rc = find_since_gap(param, st.fss_since, mdtname);
		if (rc == 0)
			rc = llapi_scan_changelog(&sc, find_since_cand_cb,
						  &st);
		if (rc < 0) {''', 'gap caller')


# ---- lreview 68418 #1: an unstriped directory's %Li/%Lo on --since/--changelog
edit(C417, PF, '''	memcpy(param->fp_lmv_md, rec->lfsr_lmv, rec->lfsr_lmvsize);
	return 0;
}
''', '''	memcpy(param->fp_lmv_md, rec->lfsr_lmv, rec->lfsr_lmvsize);
	return 0;
}

/*
 * An unstriped directory's record has no LMV.  Build the stub a walk builds,
 * which names the directory's MDT, so %Li and %Lo answer as on a walk.
 */
static void find_rec_dir_stub(struct find_param *param, bool isdir)
{
	if (!isdir || param->fp_lmv_md->lum_magic != 0 ||
	    param->fp_file_mdt_index == OBD_NOT_FOUND)
		return;
	param->fp_lmv_md->lum_magic = LMV_MAGIC_V1;
	param->fp_lmv_md->lum_stripe_offset = param->fp_file_mdt_index;
}
''', 'stub helper')
edit(C417, PF, '''	if (param->fp_mdt_uuid != NULL &&
	    param->fp_file_mdt_index == OBD_NOT_FOUND)
		return 0;
''', '''	if (param->fp_mdt_uuid != NULL &&
	    param->fp_file_mdt_index == OBD_NOT_FOUND)
		return 0;
	find_rec_dir_stub(param, isdir);
''', 'stub since')
edit(C418, PF, '''	param->fp_get_lmv = isdir && find_needs_lmv(param);

	fc.fc_rec = rec;
	/*
	 * Whatever --resolve looked up.''', '''	param->fp_get_lmv = isdir && find_needs_lmv(param);
	/* as find_since_rec_cb() has it; 0 would name MDT0000 */
	param->fp_file_mdt_index = (rec->lfsr_valid & LLAPI_SCAN_MDT_INDEX) ?
				   (int)rec->lfsr_mdt_index : OBD_NOT_FOUND;
	find_rec_dir_stub(param, isdir);

	fc.fc_rec = rec;
	/*
	 * Whatever --resolve looked up.''', 'stub changelog')

# ---- commit messages --------------------------------------------------
def para(m, text, what):
    # a paragraph before the trailers
    for t in ('\nTest-Parameters:', '\nSigned-off-by:'):
        k = m.find(t)
        if k >= 0:
            break
    if text in m:
        return m
    if k < 0:
        raise RuntimeError(what + ': no trailer')
    return m[:k] + '\n' + text + '\n' + m[k:]


def m_417(m):
    return para(m, '''llapi_find() and llapi_find_with_cb() return -EINVAL for a set
fp_since_kind instead of walking with it ignored.''', 'm417')


def m_418(m):
    m = rep(m, '''-type is the one field with a third answer.  A record says what kind''',
            '''-type has a third answer, as -name does below.  A record says what kind''',
            'm418 type')
    return para(m, '''llapi_find_with_cb() refuses fp_changelog_mdt as it refuses
fp_since_kind.''', 'm418')


def m_419(m):
    return para(m, '''llapi_find_with_cb() refuses fp_since_cookie as it refuses
fp_since_kind.''', 'm419')


def m_gap(m):
    m = rep(m, '''window. The warning then says only where the log starts and that
anything cleared after the anchor is missing.''', '''window. The warning then says only where the log starts and that
anything cleared from the anchor on is missing.''', 'mgap anchor')
    return para(m, '''If the read of the oldest record fails, the run stops as it does
when the scan itself fails.''', 'mgap')


exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       'edits_lr.py')).read())

MSG = {C159: m_159, C163: m_163, C288: m_288, C415: m_415, C417: m_417,
       C418: m_418_b, C419: m_419_b, C443: m_443, F_GAP: m_gap}


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
        for (own, a, b) in RENAMES:
            if own > i:
                continue
            out = subprocess.run(['git', '-C', REPO, 'grep', '-l', '-w', a, c],
                                 capture_output=True).stdout.decode()
            for f in out.split():
                f = f.split(':', 1)[1]
                if f not in files:
                    files[f] = git('show', '%s:%s' % (c, f)).decode()
                files[f] = re.sub(r'\b%s\b' % a, b, files[f])
        for (own, f, a, b, what) in POST:
            if own > i:
                continue
            try:
                files[f] = rep(files[f], a, b, what)
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
        idx = '/tmp/claude-1004/rb1008-index'
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
