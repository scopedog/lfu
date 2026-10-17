# AI on 68163 PS36 62de17d3: with no ZFS backend in lfs, the early --target
# check skipped all of test_300a, the scanner half too.  Carry on instead;
# the lfs find --device check below skips on the same ENOTSUP.
R = {
'lustre/tests/conf-sanity.sh': [(
"""			error "lfs find --target $mdt1svc read an imported pool"
		zfs_scan_unbuilt $scan_err &&
			skip "lfs has no zfs scan backend in this build"
		if ! grep -q "in use: pool imported" $scan_err; then
			cat $scan_err
			error "--target $mdt1svc was not refused as in use"
		fi
""",
"""			error "lfs find --target $mdt1svc read an imported pool"
		# no backend in lfs: the scanner half below still runs
		if zfs_scan_unbuilt $scan_err; then
			echo "lfs has no zfs scan backend in this build"
		elif ! grep -q "in use: pool imported" $scan_err; then
			cat $scan_err
			error "--target $mdt1svc was not refused as in use"
		fi
""")],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
