"""Temporary instrumentation: why is --changelog --resolve -size undecided?

Prints, per record, what the scan delivered and what the decider was handed.
Not for commit -- 08-resolvedbg.sh reverts it.
"""
import sys

p = sys.argv[1]
s = open(p).read()

old = '''	find_rec_to_lmd(rec, param);'''
new = '''	find_rec_to_lmd(rec, param);
	fprintf(stderr,
		"DBG rec: valid=0x%llx SIZE=%d size=%llu | lmd: FLSIZE=%d stx_size=%llu mode=0%o\\n",
		(unsigned long long)rec->sr_valid,
		!!(rec->sr_valid & LLAPI_SCAN_SIZE),
		(unsigned long long)rec->sr_size_bytes,
		!!(param->fp_lmd->lmd_flags & OBD_MD_FLSIZE),
		(unsigned long long)param->fp_lmd->lmd_stx.stx_size,
		param->fp_lmd->lmd_stx.stx_mode);'''
if old not in s:
    sys.exit("DBG: find_rec_to_lmd call site not found")
s = s.replace(old, new, 1)

old2 = '''		if (path == NULL && d == -1 && de == NULL) {
			fc->fc_undecided = true;
			return 0;
		}'''
new2 = '''		if (path == NULL && d == -1 && de == NULL) {
			fprintf(stderr,
				"DBG undecided: decision=%d gather_all=%d check_size=%d stripe_count=%d flags=0x%llx\\n",
				decision, gather_all, param->fp_check_size,
				stripe_count, (unsigned long long)flags);
			fc->fc_undecided = true;
			return 0;
		}'''
if old2 not in s:
    sys.exit("DBG: undecided site not found")
s = s.replace(old2, new2, 1)
open(p, 'w').write(s)
print("debug instrumentation inserted")
