# a-1019 lreview r2 fixes R9 (68288) and R11 (68419), applied by
# forktx5.py from 68288 up, on every branch that holds it:
#   R9  liblustreapi_scan.c: the kernel-doc says every non-VISIBLE record
#       has no path; an OST object with an owner has one (owner is checked
#       first).  Word it as llapi_scan_rec_path.3 does.
#   R11 liblustreapi_pfind.c: the cookie pre-pass refuses a cookie that
#       rename() could not replace in a sticky directory (another user's
#       cookie in /tmp).  Gated on 68419's Change-Id: the include block
#       and llapi_find_since.3's -EPERM entry exist below it.
# Idempotent: every old text is gone after one pass.
HITS = {}
ANC = frozenset()

SCAN = 'lustre/utils/liblustreapi_scan.c'
PFIND = 'lustre/utils/liblustreapi_pfind.c'
FIND1 = 'Documentation/man1/lfs-find.1'
SINCE3 = 'Documentation/man3/llapi_find_since.3'
CID_68419 = 'Ia8ce93368a2c2c8c2ea2ee88c8e7f7e099b1bfa5'


def base(path):
    raise RuntimeError('set by the driver')


R = []      # (tag, path, old, new, needs 68419)

R.append(('R9', SCAN,
''' * A record whose class is not LLAPI_SCAN_CLS_VISIBLE has no pathname: an
 * object a target keeps for itself, an agent inode, an orphan in PENDING.
''',
''' * Any other record whose class is not LLAPI_SCAN_CLS_VISIBLE has no
 * pathname: an object a target keeps for itself, an agent inode, an orphan
 * in PENDING.
''', False))

R.append(('R11inc', PFIND,
'''#include <sys/ioctl.h>
#include <sys/sysmacros.h>
''',
'''#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
''', True))

R.append(('R11inc2', PFIND,
'''#include <lustre/lustreapi.h>
#include <linux/lustre/lustre_ioctl.h>
''',
'''#include <lustre/lustreapi.h>
#include <linux/capability.h>
#include <linux/lustre/lustre_ioctl.h>
''', True))

R.append(('R11fn', PFIND,
'''/*
 * The stale-anchor check, which is the reason a cookie is worth having:
''',
'''/*
 * rename() over a file in a sticky directory, such as /tmp, needs the caller
 * to own the file or the directory, or to have CAP_FOWNER.
 */
static bool find_cookie_may_replace(const char *cookie, const struct stat *st)
{
	struct __user_cap_header_struct hdr = {
		.version = _LINUX_CAPABILITY_VERSION_3,
	};
	struct __user_cap_data_struct cap[_LINUX_CAPABILITY_U32S_3];
	char dir[PATH_MAX];
	struct stat dst;
	char *sep;

	if (st->st_uid == geteuid())
		return true;

	snprintf(dir, sizeof(dir), "%s", cookie);
	sep = strrchr(dir, '/');
	if (sep == NULL)
		snprintf(dir, sizeof(dir), ".");
	else if (sep == dir)
		dir[1] = '\\0';	/* the cookie sits in the root */
	else
		*sep = '\\0';
	if (stat(dir, &dst) != 0 || !(dst.st_mode & S_ISVTX) ||
	    dst.st_uid == geteuid())
		return true;

	return syscall(SYS_capget, &hdr, cap) == 0 &&
	       (cap[CAP_TO_INDEX(CAP_FOWNER)].effective &
		CAP_TO_MASK(CAP_FOWNER));
}

/*
 * The stale-anchor check, which is the reason a cookie is worth having:
''', True))

R.append(('R11chk', PFIND,
'''	close(fd);
	unlink(probe);

''',
'''	close(fd);
	unlink(probe);

	/* the probe passes there, but rename() over the cookie would not */
	if (lstat(cookie, &st) == 0 && !find_cookie_may_replace(cookie, &st)) {
		llapi_error(LLAPI_MSG_ERROR, -EPERM,
			    "cannot write the cookie '%s'", cookie);
		return -EPERM;
	}

''', True))

R.append(('R11man1', FIND1,
'''that does not exist is a first run and starts at the oldest surviving record;
one that cannot be written is refused before the search prints anything.
''',
'''that does not exist is a first run and starts at the oldest surviving record;
one that cannot be written is refused before the search prints anything.
So is another user's
.I FILE
in a sticky directory such as
.IR /tmp ,
which the run could not replace.
''', True))

R.append(('R11man3', SINCE3,
'''.B -EPERM
FIDs cannot be resolved through this mount.
''',
'''.B -EPERM
FIDs cannot be resolved through this mount. Also a
.I fp_since_cookie
owned by another user in a sticky directory such as
.IR /tmp ,
which
.BR rename (2)
could not replace.
''', True))


def fn(path, s, subj):
    if s is None:
        return s
    for tag, p, o, n, gate in R:
        if p != path or o not in s:
            continue
        if gate and CID_68419 not in ANC:
            continue
        # an insertion keeps its anchor: skip if already applied
        if o in n and n in s:
            continue
        assert s.count(o) == 1, (tag, subj, s.count(o))
        s = s.replace(o, n)
        HITS.setdefault(subj, []).append(tag)
    return s


M = {
    'M419': (
        '''find_cookie_read() takes for a first run, so a typo would not be
noticed until every log had been scanned.
''',
        '''find_cookie_read() takes for a first run, so a typo would not be
noticed until every log had been scanned.  In a sticky directory such
as /tmp the probe is not enough: rename() over another user's cookie
fails EPERM unless the caller owns the directory or has CAP_FOWNER, so
that is checked too.
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
