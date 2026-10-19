# a-1019 AI round: #1 #2 (68156), #5 #6 (68415), #7 #8 (68416), #9 (68419).
# String transforms applied by forktx4.py to every commit from 68156 up, on
# every branch.  Each old text must occur at most once; HITS lists where.
HITS = {}

IH = 'lustre/utils/lustreapi_internal.h'
CLC = 'lustre/utils/liblustreapi_scan_changelog.c'
CL3 = 'Documentation/man3/llapi_scan_changelog.3'
CLT = 'lustre/tests/llapi_scan_changelog_test.c'
FID3 = 'Documentation/man3/llapi_scan_fid.3'
SC = 'lustre/utils/liblustreapi_scan.c'

R = {
    # 1: the device scan accepts STOP_ON_ERROR and ignores it
    ('1', IH): (
        """ * a flag only one of them can act on cannot be quietly accepted by the other.
 * Deliberately not public:""",
        """ * a flag only one of them can act on cannot be quietly accepted by the other.
 * The exception is LLAPI_SCAN_F_STOP_ON_ERROR: a device scan accepts it and
 * ignores it, as llapi_scan_device(3) says.
 * Deliberately not public:"""),
    # 2: HSM is in the mask; 68288 rewrites this comment with it already
    ('2', IH): (
        """/* and what only one kind of target has, so a scan of the other never
 * answers for it: the layout, the directory stripe, the lazy SOM size, the
 * MDT index and the linkea with the parent it names are the MDT's.
 */""",
        """/* and what only one kind of target has, so a scan of the other never
 * answers for it: the layout, the directory stripe, the HSM state, the lazy
 * SOM size, the MDT index and the linkea with the parent it names are the
 * MDT's.
 */"""),
    # 6: lfsc_user must be cl<N> for a clear
    ('6inc', CLC): (
        """#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
""",
        """#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
"""),
    ('6fn', CLC): (
        """
/**
 * llapi_scan_changelog() - an Object Stream from one MDT's changelog
""",
        """
/* the MDS clears only by "cl<N>"; llapi_changelog_clear() drops a "-name" */
static bool scan_cl_user_is_id(const char *user)
{
	if (user == NULL || strncmp(user, "cl", 2) != 0 ||
	    !isdigit((unsigned char)user[2]))
		return false;
	for (user += 2; isdigit((unsigned char)*user); user++)
		;
	return *user == '\\0' || *user == '-';
}

/**
 * llapi_scan_changelog() - an Object Stream from one MDT's changelog
"""),
    ('6chk', CLC): (
        """	if ((scl.lfsc_flags & LLAPI_SCAN_CL_F_CLEAR) && scl.lfsc_user == NULL)
		return -EINVAL;
""",
        """	if ((scl.lfsc_flags & LLAPI_SCAN_CL_F_CLEAR) &&
	    !scan_cl_user_is_id(scl.lfsc_user))
		return -EINVAL;
"""),
    ('6man', CL3): (
        """The registered Changelog user, as
.BR cl1 .
Required by
.BR LLAPI_SCAN_CL_F_CLEAR .
""",
        """The registered Changelog user, as
.B cl1
or
.BR cl1-name .
Required by
.BR LLAPI_SCAN_CL_F_CLEAR ,
which refuses any other form, such as a bare number or name.
"""),
    ('6err', CL3): (
        """.B LLAPI_SCAN_CL_F_CLEAR
without
.IR lfsc_user ;
""",
        """.B LLAPI_SCAN_CL_F_CLEAR
without
.IR lfsc_user ;
.B LLAPI_SCAN_CL_F_CLEAR
with an
.I lfsc_user
other than
.BI cl N
or
.BI cl N - name ;
"""),
    ('6tdecl', CLT): (
        """	struct cl_result res = { 0 };
	int rc;

	/* the library says so on its own; the test knows already */
""",
        """	static const char *const bad_users[] = { "1", "cl", "cl1x", "name",
						  NULL };
	struct cl_result res = { 0 };
	int rc;
	int i;

	/* the library says so on its own; the test knows already */
"""),
    ('6tcase', CLT): (
        """	ASSERTF(rc == -EINVAL, "clear without a user returned %d", rc);
""",
        """	ASSERTF(rc == -EINVAL, "clear without a user returned %d", rc);

	/* a clear takes only cl<N>, so these fail before any record */
	for (i = 0; bad_users[i] != NULL; i++) {
		param_init(&sc);
		sc.lfsc_flags = LLAPI_SCAN_CL_F_CLEAR;
		sc.lfsc_user = bad_users[i];
		rc = llapi_scan_changelog(&sc, cl_cb, &res);
		ASSERTF(rc == -EINVAL, "clear with user '%s' returned %d",
			bad_users[i], rc);
		ASSERTF(res.cr_records == 0,
			"clear with user '%s' delivered %u records",
			bad_users[i], res.cr_records);
	}
"""),
    ('6tcount', CLT): (
        """	printf("  ten bad calls refused with -EINVAL\\n");""",
        """	printf("  fourteen bad calls refused with -EINVAL\\n");"""),
    # 7: SEE ALSO names the pages the text sends readers to
    ('7', FID3): (
        """.BR llapi_fid2path (3),
.BR llapi_scan_changelog (3),
""",
        """.BR llapi_fid2path (3),
.BR llapi_fid2path_at (3),
.BR llapi_path2fid (3),
.BR llapi_root_path_open (3),
.BR llapi_scan_changelog (3),
"""),
    # 8: the descriptor the gather opened by name is checked against @fid
    ('8code', SC): (
        """	    (!(rec.lfsr_valid & LLAPI_SCAN_FID) ||
	     !lu_fid_eq(&rec.lfsr_fid, fid))) {
		rc = -ESTALE;
		goto out;
	}
""",
        """	    (!(rec.lfsr_valid & LLAPI_SCAN_FID) ||
	     !lu_fid_eq(&rec.lfsr_fid, fid))) {
		rc = -ESTALE;
		goto out;
	}
	/* the gather opens a regular file again by name: check that too */
	if (fd >= 0) {
		struct lu_fid ofid;

		if (llapi_fd2fid(fd, &ofid) != 0 || !lu_fid_eq(&ofid, fid)) {
			rc = -ESTALE;
			goto out;
		}
	}
"""),
    ('8doc', SC): (
        """ * scan_rec_gather() still opens by pathname for LLAPI_SCAN_PROJID,
 * LLAPI_SCAN_HSM and a regular file's LLAPI_SCAN_MDT_INDEX, so for those
 * @mnt_path does decide what is read.
""",
        """ * scan_rec_gather() still opens by pathname for LLAPI_SCAN_PROJID,
 * LLAPI_SCAN_HSM and a regular file's LLAPI_SCAN_MDT_INDEX, so for those
 * @mnt_path does decide what is read.  A regular file opened this way is
 * checked against @fid too, and a mismatch is -ESTALE.  A special file's
 * project id is read through its parent and name, and is not checked.
"""),
    ('8man', FID3): (
        """regular file's MDT index are still made by pathname, through
.IR mnt_path .
""",
        """regular file's MDT index are still made by pathname, through
.IR mnt_path .
A regular file opened this way is checked against
.I fid
too. A special file's project id is read through its parent and name, and
is not checked.
"""),
}

M = {
    # 5: 68415 RESOLVE bullet reflowed
    '5': (
        """- LLAPI_SCAN_CL_F_RESOLVE fills the object's own attributes through a
  client mount: one O_PATH open by FID and a statx() or two per
  object. It
  fills only what the record lacks. The demand mask decides if the
  lookup runs at all. It needs CAP_DAC_READ_SEARCH and is refused with
  -EPERM without it. The project id, layout, LMV and HSM state are not
  filled.
""",
        """- LLAPI_SCAN_CL_F_RESOLVE fills the object's own attributes through a
  client mount: one O_PATH open by FID and a statx() or two per object.
  It fills only what the record lacks. The demand mask decides if the
  lookup runs at all. It needs CAP_DAC_READ_SEARCH and is refused with
  -EPERM without it. The project id, layout, LMV and HSM state are not
  filled.
"""),
    # 8: 68416 the claim narrowed to what is checked
    '8': (
        """handing that value back to a caller testing `if (rc)`.  The gather
runs against a pathname, so the FID it found is checked against the
one asked for, and a record never describes a different object.
""",
        """handing that value back to a caller testing `if (rc)`.  The gather
runs against a pathname, so the FID it found is checked against the
one asked for, on the getinfo and on any descriptor the gather opened.
"""),
    # 9: 68419 lfs-find.1 paragraph matches the diff
    '9': (
        """Five changes to lfs-find.1 cover all three options.  --since-cookie
moves up beside --since in SYNOPSIS and OPTIONS: it is the other way
to say where a --since search starts, where --changelog is a different
source.  TIME's spellings are given in full -- set_since() takes
eight of them, and its error text offers one the page would otherwise
not list -- and seconds are optional wherever a time appears.  And the
-name paragraph says which name a match is tested against under
--changelog: the one carried by the object's latest event that
carried a name in the same burst, so a file created as f and then
written and closed still matches -name f, its CL_CLOSE naming
nothing.  And the --since-cookie paragraph documents the refusal of a
restarted log, which this patch implements, and says
the stale check is made before the search starts, so a purge on a
later MDT during it is not caught.  EXAMPLES gains a plain --since
search.
""",
        """lfs-find.1 documents --since-cookie in SYNOPSIS, OPTIONS, the list
of options a target scan refuses, and EXAMPLES.  Its OPTIONS entry
sits beside --since: it is the other way to say where a --since
search starts, where --changelog is a different source.  The entry
documents the refusal of a restarted log, which this patch
implements, and says the stale check is made before the search
starts, so a purge on a later MDT during it is not caught.  TIME's
spellings are given in full -- set_since() takes eight of them, and
its error text offers one the page would otherwise not list -- and
seconds are optional wherever a time appears.  The -name paragraph
says which name a match is tested against under --changelog: the one
carried by the object's latest event that carried a name in the same
burst, so a file created as f and then written and closed still
matches -name f, its CL_CLOSE naming nothing.  EXAMPLES also gains a
plain --since search.
"""),
}


def fn(path, s, subj):
    for (tag, p), (o, n) in R.items():
        if p != path or o not in s:
            continue
        assert s.count(o) == 1, (tag, subj)
        if n in s and o in n:
            continue        # an insertion keeps its anchor: done already
        s = s.replace(o, n)
        HITS.setdefault(subj, []).append(tag)
    return s


def msgfn(msg, subj):
    for tag, (o, n) in M.items():
        if o in msg:
            msg = msg.replace(o, n)
            HITS.setdefault(subj, []).append('msg' + tag)
    return msg


import atexit
import sys


@atexit.register
def _report():
    for k, v in HITS.items():
        print('HITS %-60s %s' % (k[:60], ' '.join(v)), file=sys.stderr)
