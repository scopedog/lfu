"""Controls for the two --resolve fixes in 68418.

  nopath    -- drop what the lookup found back on the floor.  find_decide()
               then has no path and no descriptor, -size is undecidable, and
               "lfs find --changelog --resolve -size +0" exits 0 reporting
               nothing.  160ab's -size assertion must catch that.
  nosubtree -- remove the subtree test.  --resolve then answers for the whole
               filesystem, and 160ab's subtree assertion must catch that.

The condition is neutered rather than the call deleted wherever that would
leave something unreferenced: the tree builds with -Werror.
"""
import sys

arm, p = sys.argv[1], sys.argv[2]
s = open(p).read()

if arm == "nopath":
    old = '''	fc.fc_path = (char *)rec->sr_path;	/* read only, as elsewhere */
	fc.fc_p = rec->sr_parent_fd;
	fc.fc_d = rec->sr_fd;'''
    new = '''	fc.fc_path = NULL;	/* NOPATH ARM */
	fc.fc_p = -1;
	fc.fc_d = -1;'''
elif arm == "nosubtree":
    old = '''	if (rec->sr_path != NULL && !find_since_under(st, rec->sr_path))
		return 0;

	find_rec_to_lmd(rec, param);
	if (param->fp_lmd->lmd_lmm.lmm_magic == 0 && find_check_lmm_info(param))
		find_lmm_set_default(param);
	find_rec_to_lmv(rec, param);
	param->fp_get_lmv = (rec->sr_valid & LLAPI_SCAN_MODE) &&'''
    new = '''	if (0 /* NOSUBTREE ARM */ &&
	    rec->sr_path != NULL && !find_since_under(st, rec->sr_path))
		return 0;

	find_rec_to_lmd(rec, param);
	if (param->fp_lmd->lmd_lmm.lmm_magic == 0 && find_check_lmm_info(param))
		find_lmm_set_default(param);
	find_rec_to_lmv(rec, param);
	param->fp_get_lmv = (rec->sr_valid & LLAPI_SCAN_MODE) &&'''
else:
    sys.exit(f"unknown arm {arm}")

if old not in s:
    sys.exit(f"{arm.upper()} PATCH DID NOT MATCH")
open(p, 'w').write(s.replace(old, new, 1))
print(f"control: {arm}")
