#!/usr/bin/env python3
# Rebuild fix-1007: the 10-07 AI-round edits (proven at the fix-1007 tip)
# applied to each commit's own tree from the commit that owns each edit
# upward.  Idempotent per edit: new text present -> skip.  No cherry-picks.
import os, subprocess, sys

REPO = '/home/nishida/lfs-fix-1007'
BASE = '507b70072f^'
# 68156 .. 68420, 69443, then the four unpushed follow-ups
STACK = ['507b70072f', '41ce6d4dd3', '9b2b5a3e00', '31578b51dc',
         '58bc3dc8f4', '6d5216f95d', '25cad69896', 'b8f6b36849',
         '34bea417d0', '9f160514a9', '16140614d7', '40c2603167',
         '8792f895a8', '6e26f11543', 'ceaeec5973', '3a2a321ac3',
         'bcf1d6d101', '036735e9fb']
(C156, C157, C158, C159, C160, C163, C288, C415, C416, C417, C418, C419,
 C420, C443, F_GAP, F_NLINK, F_PICK, F_ZFS) = range(18)
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


ZF = 'lustre/utils/libscan_zfs.c'

# ---- 68163: EACCES survives ZFS 2.4's zpool_find_config() --------------
edit(C163, ZF, '''		/* the label scan skipped devices this caller cannot read */
		if (lpch.lpc_error == LPC_EACCESS)
			return -EACCES;''', '''		/*
		 * The label scan skipped devices this caller cannot read.
		 * Not lpc_error: ZFS 2.4's zpool_find_config() overwrites it.
		 */
		if (lpch.lpc_open_access_error && geteuid() != 0)
			return -EACCES;''', '163 eacces')
edit(C163, ZF, ''' * Lustre creates its pools with cachefile=none, so the config cache that
 * kernel_init() loads knows nothing and dmu_objset_own() says ENOENT; the
 * pool has to be found the way zpool import and zdb -e find it.''', ''' * scan_zfs_open() leaves no config cache loaded, so dmu_objset_own() says
 * ENOENT whatever the pool's cachefile property; the pool has to be found
 * the way zpool import and zdb -e find it.''', '163 cache')

PF = 'lustre/utils/liblustreapi_pfind.c'
LF1 = 'Documentation/man1/lfs-find.1'
LS3 = 'Documentation/man3/llapi_find_since.3'

# ---- 68419: a symlinked cookie is refused ------------------------------
edit(C419, PF, '''	/* O_NONBLOCK so a FIFO cannot hang the open */
	fd = open(file, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		/* the first run has no cookie: start at the oldest record */
		if (errno == ENOENT)
			return 0;
		return -errno;
	}''', '''	/*
	 * O_NONBLOCK so a FIFO cannot hang the open.  O_NOFOLLOW because the
	 * rename in find_cookie_write() would replace a link, not its target;
	 * a dangling link would also read as a first run.
	 */
	fd = open(file, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
	if (fd < 0) {
		/* the first run has no cookie: start at the oldest record */
		if (errno == ENOENT)
			return 0;
		if (errno == ELOOP) {
			llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO,
				    -EINVAL,
				    "the cookie '%s' is not a regular file",
				    file);
			return -EINVAL;
		}
		return -errno;
	}''', '419 nofollow')
edit(C419, PF, '''	if (stat(cookie, &st) == 0 && !S_ISREG(st.st_mode)) {''',
     '''	if (lstat(cookie, &st) == 0 && !S_ISREG(st.st_mode)) {''',
     '419 lstat')
edit(C419, LF1, '''.I FILE
that is not a regular file is refused too.''', '''.I FILE
that is not a regular file, a symbolic link included, is refused too.''',
     '419 man1 symlink')
edit(C419, LS3, '''on a filesystem with more than one MDT. Also for a cookie that is not a
regular file, or that was written for another filesystem or another search
root.''', '''on a filesystem with more than one MDT. Also for a cookie that is not a
regular file (a symbolic link is not one), or that was written for another
filesystem or another search root.''', '419 man3 symlink')

# ---- 68419: a persistent per-object error holds the cookie -------------
edit(C419, LF1, '''Keep
.I FILE
outside the searched tree;''', '''An object that cannot be read (an error other than its having gone) is
reported at the end and leaves
.I FILE
as it was, so the next run prints the same matches again. An error that
persists, such as an object the caller may not read, holds the anchors
there on every run until it is fixed or the log is purged past them.
Keep
.I FILE
outside the searched tree;''', '419 man1 stuck')
edit(C419, LS3, '''An error reading an MDT's changelog is returned as it came.''',
     '''An error reading an MDT's changelog is returned as it came. An error
on one object does not end the search: the first is returned once it is
done, and
.I fp_since_cookie
is not rewritten, so the next call reports the same matches again. An
error that persists holds the anchors there on every call until it is
fixed or the log is purged past them, which is then
.BR -ESTALE .''', '419 man3 stuck')

SC = 'lustre/utils/liblustreapi_scan_changelog.c'
SC3 = 'Documentation/man3/llapi_scan_changelog.3'

# ---- 68415: the replaced object's record carries no source -------------
edit(C415, SC, '''	if (r->cr_flags & CLF_RENAME) {
		struct changelog_ext_rename *rn = changelog_rec_rename(r);

		if (fid_is_sane(&rn->cr_sfid)) {''', '''	if (r->cr_flags & CLF_RENAME) {
		struct changelog_ext_rename *rn = changelog_rec_rename(r);
		/* mv c d over d: old d did not come from c */
		bool replaced = r->cr_type != CL_MIGRATE && fid != NULL &&
				!lu_fid_eq(fid, &rn->cr_sfid);

		if (fid_is_sane(&rn->cr_sfid) && !replaced) {''', '415 src')
edit(C415, SC3, '''= the one that moved, in event mode as in object mode. A''', '''= the one that moved, in event mode as in object mode. Only the second
carries the source fields; the replaced object did not come from
.IR a .
A''', '415 man src')

SCT = 'lustre/tests/llapi_scan_changelog_test.c'
edit(C415, SCT, '''	unsigned int	rn_victim_hits;
};''', '''	unsigned int	rn_victim_hits;
	unsigned int	rn_over_src;	/* of rn_over_hits, with a source */
	unsigned int	rn_victim_src;
};''', '415 t8 fields')
edit(C415, SCT, '''	if (fid_same(&rec->lfsr_fid, &res->rn_over))
		res->rn_over_hits++;
	if (fid_same(&rec->lfsr_fid, &res->rn_victim))
		res->rn_victim_hits++;
	return 0;''', '''	if (fid_same(&rec->lfsr_fid, &res->rn_over)) {
		res->rn_over_hits++;
		if (rec->lfsr_valid & LLAPI_SCAN_EVENT_SRC)
			res->rn_over_src++;
	}
	if (fid_same(&rec->lfsr_fid, &res->rn_victim)) {
		res->rn_victim_hits++;
		if (rec->lfsr_valid & LLAPI_SCAN_EVENT_SRC)
			res->rn_victim_src++;
	}
	return 0;''', '415 t8 cb')
edit(C415, SCT, '''		"the object replaced: %u records in event mode, %u in object mode",
		ev.rn_victim_hits, ob.rn_victim_hits);
''', '''		"the object replaced: %u records in event mode, %u in object mode",
		ev.rn_victim_hits, ob.rn_victim_hits);
	/* only the object that moved came from somewhere */
	ASSERTF(ev.rn_over_src == 1 && ob.rn_over_src == 1,
		"the object renamed over a name: %u/%u records carry its source",
		ev.rn_over_src, ob.rn_over_src);
	ASSERTF(ev.rn_victim_src == 0 && ob.rn_victim_src == 0,
		"the object replaced: %u/%u records carry a source",
		ev.rn_victim_src, ob.rn_victim_src);
''', '415 t8 assert')

SAN = 'lustre/tests/sanity.sh'

# ---- 68420: purge-dependent cases, and refusals pinned to their text ---
GUARD = '''	# changelog_clear purges only when this test's user is the only one
	local i
	for ((i = 1; i <= MDSCOUNT; i++)); do
		changelog_users mds$i | grep -q "^cl" &&
			skip "active changelog user on mds$i"
	done

'''
edit(C420, SAN, '''	local m=$MOUNT
	local out

	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $tdir failed"

	changelog_register || error "changelog_register failed"
	changelog_chmask "ALL"''', '''	local m=$MOUNT
	local out

''' + GUARD + '''	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $tdir failed"

	changelog_register || error "changelog_register failed"
	changelog_chmask "ALL"''', '420 guard Ab')
edit(C420, SAN, '''	local ck=$TMP/lfs-find-cookie.$$
	local out
	local sum

	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $tdir failed"''', '''	local ck=$TMP/lfs-find-cookie.$$
	local out
	local sum

''' + GUARD + '''	mkdir_on_mdt0 $DIR/$tdir || error "mkdir $tdir failed"''',
     '420 guard Ac')
edit(C420, SAN, '''	$LFS find $DIR/$tdir --since-cookie $ck.noroot -type f &> /dev/null &&
		error "a cookie with no root should be refused"
''', '''	out=$($LFS find $DIR/$tdir --since-cookie $ck.noroot -type f 2>&1) &&
		error "a cookie with no root should be refused"
	grep -q "names no search root" <<< "$out" ||
		error "refused for another reason: $out"
''', '420 noroot')
edit(C420, SAN, '''		# lfs find --since-cookie for ${FSNAME}x
		${FSNAME}x-MDT0000 7
	EOF
	$LFS find $DIR/$tdir --since-cookie $ck.other -type f &> /dev/null &&
		error "a cookie for another filesystem should be refused"
''', '''		# lfs find --since-cookie for ${FSNAME}x under $DIR/$tdir
		${FSNAME}x-MDT0000 7
	EOF
	out=$($LFS find $DIR/$tdir --since-cookie $ck.other -type f 2>&1) &&
		error "a cookie for another filesystem should be refused"
	grep -q "is a cookie for '${FSNAME}x'" <<< "$out" ||
		error "refused for another reason: $out"
''', '420 other fs')

# ---- 69443: one purge test for both callers ----------------------------
# The gap follow-up gave find_cl_first() a fourth argument, so each edit is
# spelt twice: three arguments up to it, NULL from it on.
PURGE = []


def E(f, old, new, what):
    PURGE.append((f, old, new, what))


E( PF, '''/*
 * The stale-anchor check, which is the reason a cookie is worth having:''', '''/*
 * Has @mdtname purged past @anchor?  The scan starts one past the anchor, so
 * an oldest record above anchor + 1 means the records between are gone.
 *
 * Return: 0, -ESTALE (said here), or the errno reading the log.  @oldest is
 * 0 for an empty log.
 */
static int find_cookie_purged(const char *mdtname, __u64 anchor,
			      const char *cookie, __u64 *oldest)
{
	int rc;

	*oldest = 0;
	rc = find_cl_first(mdtname, 0, oldest@A@);
	if (rc < 0) {
		llapi_error(LLAPI_MSG_ERROR, rc,
			    "cannot read the changelog of '%s'", mdtname);
		return rc;
	}
	if (*oldest > anchor + 1) {
		llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ESTALE,
			    "'%s' has purged past the cookie: it starts at %llu and '%s' records %llu, so the records in between are gone; '%s' is left where it was",
			    mdtname, (unsigned long long)*oldest, cookie,
			    (unsigned long long)anchor, cookie);
		return -ESTALE;
	}

	return 0;
}

/*
 * The stale-anchor check, which is the reason a cookie is worth having:''',
     '443 helper')
E( PF, ''' * Every MDT is checked before any of them is scanned.  Done inside the scan,
 * the refusal would arrive with the earlier MDTs' matches already on stdout
 * and no cookie written, so the next run would repeat them.  It costs one
 * record per MDT, and none at all for an MDT with no anchor yet: 0 has
 * nothing to be stale against, and that is also every MDT of a first run.''', ''' * Every MDT is checked before any of them is scanned.  Done inside the scan,
 * the refusal would arrive with the earlier MDTs' matches already on stdout
 * and no cookie written, so the next run would repeat them.  It reads up to
 * two records per anchored MDT, and none for an MDT with no anchor yet: 0
 * has nothing to be stale against, and that is also every MDT of a first
 * run.  llapi_find_since() reads one more before each later MDT, for a
 * purge during the run.''',
     '443 check comment')
E( PF, '''		snprintf(mdtname, sizeof(mdtname), "%s-MDT%04x", fsname,
			 mdts[i]);
		rc = find_cl_first(mdtname, 0, &oldest@A@);
		if (rc < 0) {
			llapi_error(LLAPI_MSG_ERROR, rc,
				    "cannot read the changelog of '%s'",
				    mdtname);
			return rc;
		}
		/* the scan starts one past the anchor: see the caller */
		if (oldest > anchor + 1) {
			llapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO,
				    -ESTALE,
				    "'%s' has purged past the cookie: it starts at %llu and '%s' records %llu, so the run would resume at %llu and the records in between are gone",
				    mdtname, (unsigned long long)oldest, cookie,
				    (unsigned long long)anchor,
				    (unsigned long long)(anchor + 1));
			return -ESTALE;
		}
		if (oldest == 0)''', '''		snprintf(mdtname, sizeof(mdtname), "%s-MDT%04x", fsname,
			 mdts[i]);
		rc = find_cookie_purged(mdtname, anchor, cookie, &oldest);
		if (rc < 0)
			return rc;
		if (oldest == 0)''', '443 check uses')
E( PF, '''		if (i > 0 && param->fp_since_cookie != NULL &&
		    starts[mdts[i]] != 0) {
			__u64 oldest = 0;

			rc = find_cl_first(mdtname, 0, &oldest@A@);
			if (rc < 0) {
				llapi_error(LLAPI_MSG_ERROR, rc,
					    "cannot read the changelog of '%s'",
					    mdtname);
				break;
			}
			if (oldest > starts[mdts[i]] + 1) {
				rc = -ESTALE;
				llapi_error(LLAPI_MSG_ERROR |
					    LLAPI_MSG_NO_ERRNO, rc,
					    "'%s' purged past the cookie during this run: it starts at %llu, but '%s' records %llu, so the records in between are gone; '%s' is left where it was",
					    mdtname, (unsigned long long)oldest,
					    param->fp_since_cookie,
					    (unsigned long long)starts[mdts[i]],
					    param->fp_since_cookie);
				break;
			}
		}''', '''		if (i > 0 && param->fp_since_cookie != NULL &&
		    starts[mdts[i]] != 0) {
			__u64 oldest;

			rc = find_cookie_purged(mdtname, starts[mdts[i]],
						param->fp_since_cookie,
						&oldest);
			if (rc < 0)
				break;
		}''', '443 loop uses')


E(PF, '''	 * @cookie is never NULL: the one caller tests it before calling, and
	 * the -ESTALE message below hands it to %s unguarded.''', '''	 * @cookie is never NULL: the one caller tests it before calling, and
	 * find_cookie_purged()'s -ESTALE message hands it to %s unguarded.''',
  '443 null note')


def purge_edits(own, until, A):
    for (f, old, new, what) in PURGE:
        edit(own, f, old.replace('@A@', A), new.replace('@A@', A), what,
             until)


purge_edits(C443, F_GAP, '')
purge_edits(F_GAP, None, ', NULL')
LFS = 'lustre/utils/lfs.c'

# ---- 68417: --since on a sweep is refused once, in lfs ------------------
XATTR = '''	if (param->fp_xattr_match_info != NULL) {
		fprintf(stderr, "%s: --xattr needs a mounted filesystem\\n",
			argv[0]);
		return -ENOTSUP;
	}
'''
SINCE_TAIL = '''	if (what != NULL) {
		fprintf(stderr,
			"%s: %s needs a changelog, which a target scan has not\\n",
			argv[0], what);
		return -ENOTSUP;
	}
'''
edit(C417, LFS, XATTR, XATTR + '''	if (param->fp_since_kind != LLAPI_SINCE_NONE) {
		fprintf(stderr,
			"%s: --since needs a changelog, which a target scan has not\\n",
			argv[0]);
		return -ENOTSUP;
	}
''', '417 lfs since', until=C418)
edit(C418, LFS, XATTR, XATTR + '''	if (param->fp_since_kind != LLAPI_SINCE_NONE)
		what = "--since";
	else if (param->fp_changelog_mdt != NULL)
		what = "--changelog";
''' + SINCE_TAIL, '418 lfs since', until=C419)
edit(C419, LFS, XATTR, XATTR + '''	if (param->fp_since_kind != LLAPI_SINCE_NONE)
		what = "--since";
	else if (param->fp_since_cookie != NULL)
		what = "--since-cookie";
	else if (param->fp_changelog_mdt != NULL)
		what = "--changelog";
''' + SINCE_TAIL, '419 lfs since')

edit(C418, LFS, '''	const char *device = param->fp_device;
	int scanned = 0;''', '''	const char *device = param->fp_device;
	const char *what = NULL;
	int scanned = 0;''', '418 lfs what')

# ---- 68159: llapi_find_device(3) passes back llapi_scan_device(3)'s ---
edit(C159, 'Documentation/man3/llapi_find_device.3', '''.B -EIO
the target could not be read.
.SH NOTES''', '''.B -EIO
the target could not be read.
.LP
Any other error
.BR llapi_scan_device (3)
returns is passed back as well;
.BR -EACCES ,
a device the caller cannot read, is the one a non-root caller meets first.
.SH NOTES''', '159 errors')

# ---- 68417: a subset of the objects, and the trailing slash -----------
edit(C417, LF1, '''without this one. The result is a strict subset of the same search without
.BR --since :
narrowed, never different. An object''', '''without this one. The objects reported are a subset of those the same search
without
.B --since
reports, never a different set. A file with several links is printed once,
not once per link, and a path given with a trailing slash is printed without
it. An object''', '417 man1 subset')
edit(C417, LS3, '''such a file once per directory entry and prints it once per link, so the
objects answered for are a subset of the same search without an anchor while
the lines printed are not a subset of its lines.''', '''such a file once per directory entry and prints it once per link, so this
prints one line where the walk prints several.''', '417 man3 subset')


def m_417(m):
    return rep(m, '''and judges each the same way: the objects are a strict subset,
narrowed and never different.  The lines are not a subset of the
lines -- a walk reaches a hardlinked file once per directory entry
and prints it once per link, while --since reaches it once per FID
and prints it once, under the first of its names that is under the
root and matches.''', '''and judges each the same way: the objects are a subset, never a
different set.  A hardlinked file is printed once rather than once
per link -- a walk reaches it once per directory entry, while --since
reaches it once per FID and prints the first of its names that is
under the root and matches.''', 'm417 subset')


def m_415(m):
    m = rep(m, '''lfsr_event_gid, not lfsr_uid: mdd_changelog_ns_store() fills the''',
            '''lfsr_event_gid, not lfsr_stx.stx_uid: mdd_changelog_ns_store() fills the''',
            'm415 uid1')
    m = rep(m, '''lfsr_uid means in every scanner that fills it and what lfs find -uid
matches. Delivering it as lfsr_uid would have''', '''stx_uid means in every scanner that fills it and what lfs find -uid
matches. Delivering it as stx_uid would have''', 'm415 uid2')
    m = rep(m, '''behind three new validity bits.  An event
time is not an object time, so it does not land in lfsr_mtime: a''', '''behind four new validity bits.  An event
time is not an object time, so it does not land in stx_mtime: a''',
            'm415 bits')
    return m

# ---- 68419: comments say why, not what an earlier revision did ---------
edit(C419, PF, '''	__u64			*fss_reached;	/* this MDT's highest index */''',
     '''	/* this MDT's highest index */
	__u64			*fss_reached;''', '419 reached col')
edit(C419, PF, ''' * newline: only '/' and NUL are excluded from a name.  Written raw it ended
 * the line, so the root read back short and every run after the first was
 * refused naming a path the caller never gave -- the space case one
 * character further out -- while the remainder became its own line and was
 * dropped as unparsable.''', ''' * newline: only '/' and NUL are excluded from a name.  Written raw, a
 * newline would end the line: the root would read back short, every later
 * run would be refused naming a path the caller never gave, and the rest
 * would be dropped as an unparsable line.''', '419 raw newline')
edit(C419, PF, '''		 * "<fsname>-MDT0000_UUID" both anchored MDT0000 at an index''',
     '''		 * "<fsname>-MDT0000_UUID" would both anchor MDT0000 at an index''',
     '419 %4x')
edit(C419, PF, ''' * A record without an index is not index 0.  Storing 0 for it made a log that
 * has records indistinguishable from one that has none, and 0 compares false
 * against every anchor, so the stale check below was skipped in both cases --
 * silently, on the one guard that exists to stop a short answer.  The scan was
 * asked for LLAPI_SCAN_EVENT, so its absence is a protocol error to report
 * rather than a value to record.''',
     ''' * A record without an index is not index 0.  Storing 0 for it would make a
 * log that has records look like one that has none, and 0 compares false
 * against every anchor, so the stale check below would be skipped in both
 * cases -- silently, on the one guard that exists to stop a short answer.
 * The scan was asked for LLAPI_SCAN_EVENT, so its absence is a protocol
 * error to report rather than a value to record.''',
     '419 index 0')
edit(C419, PF, '''	 * the job user in a root-owned 0755 directory passed that test and
	 * then failed EACCES after every match had been printed.''',
     '''	 * the job user in a root-owned 0755 directory would pass that test
	 * and then fail EACCES after every match had been printed.''',
     '419 probe')
edit(C419, PF, '''	 * The anchor takes every record, marks included: taken in the
	 * callback it lagged the end of the log by whatever trailing run of
	 * records the callback does not see the scan finished on, and the
	 * next run re-read them to report them again.  Coalesced, a record
	 * carries its object's latest index and can arrive after a higher
	 * one, so only the highest is kept.''',
     '''	 * The anchor takes every record, marks included.  Taken in the
	 * callback, it would lag the end of the log by any trailing records
	 * the callback does not see, and the next run would report them
	 * again.  Coalesced, a record carries its object's latest index and
	 * can arrive after a higher one, so only the highest is kept.''',
     '419 filter anchor')
edit(C419, PF, '''		 * What is left for this one is what fopen() passed up.''',
     '''		 * What is left for this one is what the open or read of the
		 * file passed up.''', '419 open or read')
edit(C419, PF, '''		 * is, so the next run starts one past it.  Starting at it
		 * instead reported the last object of every run again in the
		 * next one.''', '''		 * is, so the next run starts one past it, or it would report
		 * the last object of every run again.''', '419 startrec')

# ---- 69443: a missing verb ---------------------------------------------
edit(C443, LF1, '''and the purge test again just before each later MDT is read: a purge that
reaches it while an earlier one is being read is refused then.''',
     '''and the purge test runs again just before each later MDT is read: a purge
that reaches it while an earlier one is being read is refused then.''',
     '443 man1 verb')


def m_419(m):
    return rep(m, '''LU-20650 lfs: find --since-cookie, per-MDT anchor''',
               '''LU-20650 lfs: add find --since-cookie, a per-MDT anchor''',
               'm419 subject')


def m_420(m):
    m = rep(m, '''holds only the lazy one, and a resolution that did not glimpse left
every object "could not be decided" while still exiting 0.  It also
asserts -printf's %s, which reads the same size through a widened
gather, that --projid is answered rather than failing on the first
record, and that''', '''holds only the lazy one, and a resolution that does not glimpse
would leave every object "could not be decided" while still exiting
0.  It also asserts -printf's %s, which reads the same size through a
widened gather, that --projid is answered, and that''', 'm420 glimpse')
    m = rep(m, '''widened gather, that --projid is answered, and that a subtree search under --resolve answers for that
subtree and not the whole filesystem.''', '''widened gather, that --projid is answered, and that a subtree search
under --resolve answers for that subtree and not the whole
filesystem.''', 'm420 wrap')
    m = rep(m, '''LU-20650 tests: sanity cases for find's changelog flags''',
            '''LU-20650 tests: add sanity cases for lfs find's changelog flags''',
            'm420 subject')
    m = rep(m, '''Four changes to lfs-find.1 come with the tests.''',
            '''Five changes to lfs-find.1 come with the tests.''', 'm420 five')
    m = rep(m, '''"nothing changed since" is never true -- which is what hid an
off-by-one in the cookie until a narrow mask made every run repeat
the last object of the one before it.''', '''"nothing changed since" is never true; the narrow mask is what lets
the third run be asserted empty.''', 'm420 mask')
    return m


def m_443(m):
    return rep(m, '''So the oldest record is read again just before each later MDT is
scanned, with the same one-record scan and the same purge test.''',
               '''So llapi_find_since() reads the oldest record again just before each
later MDT is scanned, through find_cookie_purged(), the purge test
find_cookie_check() now shares: one find_cl_first() record each.''',
               'm443 names')

# ---- lreview 68418: a lookup that fails still prints the match ---------
edit(C418, PF, '''			 * pathname.  llapi_find_device() refuses a mount of
			 * the wrong filesystem before the scan starts, which
			 * is the only place the two can be told apart.
			 */
			if (*fc->fc_path_rc == 0) {''', '''			 * pathname.  llapi_find_device() refuses a mount of
			 * the wrong filesystem before the scan starts, which
			 * is the only place the two can be told apart.
			 *
			 * Under --changelog the record is still the answer,
			 * so it is printed by FID as above; the error still
			 * fails the run.
			 */
			if (fc->fc_fid_when_lost &&
			    (fc->fc_rec->lfsr_valid & LLAPI_SCAN_FID)) {
				llapi_printf(LLAPI_MSG_NORMAL, DFID"%c",
					     PFID(&fc->fc_rec->lfsr_fid),
					     param->fp_zero_end ? '\\0' : '\\n');
				if (fc->fc_unresolved != NULL)
					(*fc->fc_unresolved)++;
			}
			if (*fc->fc_path_rc == 0) {''', 'lr418 fid on error')

# ---- lreview 68417: the man3 example allocates; the device is root's ---
edit(C417, LS3, '''.EX
        struct find_param param = { 0 };
        int rc;
\\&
        param.fp_max_depth   = (unsigned int)-1;
        param.fp_type        = S_IFREG;
        param.fp_since_kind  = LLAPI_SINCE_TIME;
        param.fp_since_time  = time(NULL) - 2 * 60 * 60;
\\&
        rc = llapi_find_since("/mnt/lustre/data", &param);
.EE''', '''.EX
        #include <lustre/lustreapi.h>
\\&
        struct find_param *param = llapi_find_param_alloc();
        int rc;
\\&
        if (param == NULL)
                return \\-ENOMEM;
        param\\->fp_max_depth   = (unsigned int)\\-1;
        param\\->fp_type        = S_IFREG;
        param\\->fp_since_kind  = LLAPI_SINCE_TIME;
        param\\->fp_since_time  = time(NULL) \\- 2 * 60 * 60;
\\&
        rc = llapi_find_since("/mnt/lustre/data", param);
        llapi_find_param_free(param);
.EE''', 'lr417 example')
edit(C418, LS3, '''.EX
        struct find_param param = { 0 };
        int rc;
\\&
        param.fp_max_depth      = (unsigned int)-1;
        param.fp_type           = S_IFREG;
        param.fp_changelog_mdt  = "lustre-MDT0000";
\\&
        /* the mount, not a subtree: a record carries no pathname.
         * Set param.fp_resolve to search below it, at one lookup
         * per object.
         */
        rc = llapi_find_since("/mnt/lustre", &param);
.EE''', '''.EX
        struct find_param *param = llapi_find_param_alloc();
        int rc;
\\&
        if (param == NULL)
                return \\-ENOMEM;
        param\\->fp_max_depth      = (unsigned int)\\-1;
        param\\->fp_type           = S_IFREG;
        param\\->fp_changelog_mdt  = "lustre\\-MDT0000";
\\&
        /* the mount, not a subtree: a record carries no pathname.
         * Set param\\->fp_resolve to search below it, at one lookup
         * per object.
         */
        rc = llapi_find_since("/mnt/lustre", param);
        llapi_find_param_free(param);
.EE''', 'lr418 example')
edit(C417, LS3, '''and
.BR lctl (8).
.LP
Resolving each candidate's FID''', '''and
.BR lctl (8).
The changelog device is readable by root alone by default, so another
caller gets
.B \\-EACCES
from the first MDT, before any FID is resolved.
.LP
Resolving each candidate's FID''', 'lr417 root', until=F_GAP)
edit(F_GAP, LS3, '''and
.BR lctl (8).
.LP
Another user may have cleared''', '''and
.BR lctl (8).
The changelog device is readable by root alone by default, so another
caller gets
.B \\-EACCES
from the first MDT, before any FID is resolved.
.LP
Another user may have cleared''', 'lr417 root gap')

# ---- lreview 68419: keep the cookie off the searched filesystem --------
edit(C419, LF1, '''outside the searched tree; the run writes it, so inside the tree it reports
itself on every run. To accept the gap and go on, remove''', '''off the filesystem being searched: the run writes it through a temporary,
so there every run sees its own writes as changes \\(em matches inside the
tree, and objects that "no longer exist" outside it. To accept the gap and
go on, remove''', 'lr419 cookie place')

# ---- lreview 68420: assertions that can fail ---------------------------
edit(C420, SAN, '''	out=$($LFS find $m --since 2m) || error "lfs find --since failed"
	grep -qF "$gonefid" <<< "$out" &&
		error "--since reported $gonefid, which no longer exists"
''', '''	# --since never prints a FID, so it is the count that says it was seen
	out=$($LFS find $m --since 2m 2> $TMP/$tfile.err) ||
		error "lfs find --since failed"
	grep -qF "$gonefid" <<< "$out" &&
		error "--since reported $gonefid, which no longer exists"
	grep -q "no longer exist" $TMP/$tfile.err ||
		error "--since did not count $gonefid as gone"
	rm -f $TMP/$tfile.err
''', 'lr420 gone')
edit(C420, SAN, '''	[[ -n "$found" ]] ||
		error "--changelog -name g did not report the renamed file"''',
     '''	grep -q "/$tdir/a/g$" <<< "$found" ||
		error "--changelog -name g missed the renamed file: '$found'"''',
     'lr420 160Ae path')
edit(C419, LF1, '''Nor is one record lost to a race in the MDT:''',
     '''Nor is a record lost to a race in the MDT caught:''', 'lr419 race')


def m_418(m):
    return rep(m, '''LU-20650 lfs: find --changelog, the log as source''',
               '''LU-20650 lfs: add find --changelog, the log as source''',
               'm418 subject')

# ---- lreview gap: record 1 means nothing lost since the log started ----
edit(F_GAP, PF, ''' * answer may be short, so say so.  Changelog indexes start at 1: a log that
 * still holds record 1 has lost nothing.  A warning, not a refusal: unlike''',
     ''' * answer may be short, so say so.  Changelog indexes start at 1: a log that
 * still holds record 1 has lost nothing since it (re)started -- a log is
 * restarted at 1 when its last user goes and the MDT is remounted, and what
 * it held before is not seen.  A warning, not a refusal: unlike''',
     'lrgap code')
edit(F_GAP, LS3, '''the cleared records may all be older than the window. A log that still
holds record 1 has lost nothing, so a new filesystem gives no warning.''',
     '''the cleared records may all be older than the window. A log that still
holds record 1 has lost nothing since it started, so a new filesystem gives
no warning; neither does a log restarted at 1, though what it held before
the restart is gone.''', 'lrgap man3')


def m_gap(m):
    return rep(m, '''check uses. Changelog indexes start at 1, so a log that still holds
record 1 has lost nothing, and a new filesystem gives no warning.''',
               '''check uses. Changelog indexes start at 1, so a log that still holds
record 1 has lost nothing since it started, and a new filesystem gives
no warning. Nor does a log restarted at 1, after its last user went and
the MDT was remounted.''', 'mgap')


# ---- commit messages --------------------------------------------------
MSG = {C415: m_415, C417: m_417, C418: m_418, C419: m_419, C420: m_420,
       C443: m_443, F_GAP: m_gap}


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
        idx = '/tmp/claude-1004/rb1007-index'
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


def tip():
    # Apply every edit that reaches the top of the stack to the worktree.
    n = len(STACK) - 1
    fail = False
    for (own, f, old, new, what, until) in EDITS:
        if until is not None and n >= until:
            continue
        p = os.path.join(REPO, f)
        s = open(p).read()
        try:
            t = rep(s, old, new, what)
        except Exception as e:
            print('tip: %s' % e)
            fail = True
            continue
        if t != s:
            open(p, 'w').write(t)
            print('tip: applied', what)
    sys.exit(1 if fail else 0)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'tip':
        tip()
    dry = len(sys.argv) > 1 and sys.argv[1] == 'dry'
    fail, tip = build(dry)
    if fail:
        sys.exit(1)
    if not dry:
        print('TIP', tip)
