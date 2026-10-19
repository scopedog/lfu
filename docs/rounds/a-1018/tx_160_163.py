# AI on 68160 PS38 768567ff: test_300a's svc is mdt1svc again.
# AI on 68160 PS38 20098768: test_300c runs lfs on ost1 with no OST guard.
# AI on 68163 PS37 f8d7ad60: EEXIST from spa_import() is not another
#   thread's import; the second own() above already caught that.
CS = 'lustre/tests/conf-sanity.sh'
ZFS = 'lustre/utils/libscan_zfs.c'
R = {
CS: [(
"""	local svc=$(facet_svc mds1)

	do_facet mds1 "$LFS find --target $svc --type f" \\
		> /dev/null 2> $scan_err &&
		error "lfs find --target $svc answered with $svc stopped"
	grep -q "no target '$svc' mounted here" $scan_err || {
		cat $scan_err
		error "lfs find --target did not say $svc is not mounted"
	}
""",
"""	do_facet mds1 "$LFS find --target $mdt1svc --type f" \\
		> /dev/null 2> $scan_err &&
		error "lfs find --target $mdt1svc answered with it stopped"
	grep -q "no target '$mdt1svc' mounted here" $scan_err || {
		cat $scan_err
		error "lfs find --target did not say $mdt1svc is not mounted"
	}
"""), (
"""	remote_mds_nodsh && skip "remote MDS with nodsh"
	(( MDS1_VERSION >= $(version_code 2.17.58) )) ||
		skip "Need MDS >= 2.17.58 for lfs find --local"
""",
"""	remote_mds_nodsh && skip "remote MDS with nodsh"
	remote_ost_nodsh && skip "remote OST with nodsh"
	(( MDS1_VERSION >= $(version_code 2.17.58) )) ||
		skip "Need MDS >= 2.17.58 for lfs find --local"
	(( OST1_VERSION >= $(version_code 2.17.58) )) ||
		skip "Need OST >= 2.17.58 for lfs find --local"
""")],
ZFS: [(
"""	/* another thread of this process imported it first */
	if (err == EEXIST)
""",
"""	/*
	 * Already imported in this process: the dmu_objset_own() that
	 * follows says whether the dataset is in it.
	 */
	if (err == EEXIST)
""")],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            assert s.count(o) == 1, path
            s = s.replace(o, n)
    return s
