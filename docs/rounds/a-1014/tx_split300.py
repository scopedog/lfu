# adilger on 68156 PS30 (conf-sanity.sh): parts of test_300 that cannot run
# echo and carry on, so the test reports success for what it did not do.
# Split them into subtests that skip: 300a the MDT (and lfs find over it),
# 300b the OST, 300c the --local sweep.  test_300 has three shapes in the
# series (68156, 68160, 68163 on); each is rewritten wherever it appears.
P = 'lustre/tests/conf-sanity.sh'
OST_START = '\t# an OST has no namespace, so what it delivers by default is its data\n'
SWEEP_START = '\t# a --local sweep with --ost or --mdt reads only targets of that type,\n'

def cut_if_block(s, start):
    """Cut the comment at start through the 'fi' closing its if/else."""
    i = s.index(start)
    j = s.index('\n\tfi\n', i) + len('\n\tfi\n')
    return s[:i] + s[j:].lstrip('\n'), s[i:j]

def dedent(block):
    return ''.join(l[1:] if l.startswith('\t') else l for l in block.splitlines(True))

def ost_body(block, zfs):
    """The scan inside 'else ... fi' of the OST block."""
    inner = block[block.index('\telse\n') + len('\telse\n'):block.rindex('\tfi\n')]
    if zfs:
        o = ('\t\t\tif [[ "$ost1_FSTYPE" == zfs ]] &&\n'
             '\t\t\t   zfs_scan_unbuilt $scan_err; then\n'
             '\t\t\t\techo "not scanning ost1: no zfs scan backend"\n'
             '\t\t\telse\n'
             '\t\t\t\tcat $scan_err\n'
             '\t\t\t\terror "scanning $(ostdevname 1) failed"\n'
             '\t\t\tfi\n')
        assert inner.count(o) == 1
        inner = inner.replace(o,
            '\t\t\t[[ "$ost1_FSTYPE" == zfs ]] && zfs_scan_unbuilt $scan_err &&\n'
            '\t\t\t\tskip "no zfs scan backend in this build"\n'
            '\t\t\tcat $scan_err\n'
            '\t\t\terror "scanning $(ostdevname 1) failed"\n')
    return dedent(inner)

def t300b(block, zfs):
    fs = ('\t[[ "$ost1_FSTYPE" == ldiskfs || "$ost1_FSTYPE" == zfs ]] ||\n'
          '\t\tskip "$ost1_FSTYPE has no scan backend"\n') if zfs else \
         '\t[ "$ost1_FSTYPE" == ldiskfs ] || skip "ldiskfs only test"\n'
    errv = '\tlocal scan_err=$TMP/$tfile.scanerr\n' if zfs else ''
    trap = '\n\tstack_trap "rm -f $TMP/$tfile.*"\n' if zfs else ''
    return ('test_300b() {\n' + fs +
            '\tremote_ost_nodsh && skip "remote OST with nodsh"\n'
            '\t(( OST1_VERSION >= $(version_code 2.17.58) )) ||\n'
            '\t\tskip "Need OST >= 2.17.58 for a target scan"\n'
            '\n'
            '\tlocal scanner=${SCANNER:-$LUSTRE/tests/llapi_scan_device_test}\n'
            + errv + trap +
            '\n'
            '\tis_mounted $MOUNT || setup_noconfig\n'
            '\tcheck_mount || error "check_mount failed"\n'
            '\tcreatemany -o $DIR/$tfile- 100 || error "createmany failed"\n'
            '\tstopall\n'
            '\tstack_trap setupall\n'
            '\n'
            '\t# an OST has no namespace, so what it delivers by default is its data\n'
            '\t# objects; a scan that returned nothing here would look like success\n'
            + ost_body(block, zfs) +
            '}\n'
            'run_test 300b "llapi_scan_device reads an OST\'s data objects"\n')

def t300c(block):
    inner = block[block.index('\t   [[ $(facet_active_host mds1) == $(facet_active_host ost1) ]]; then\n')
                  + len('\t   [[ $(facet_active_host mds1) == $(facet_active_host ost1) ]]; then\n'):
                  block.rindex('\telse\n')]
    return ('test_300c() {\n'
            '\t# ldiskfs only: a ZFS pool in use is refused\n'
            '\t[[ "$mds1_FSTYPE" == ldiskfs && "$ost1_FSTYPE" == ldiskfs ]] ||\n'
            '\t\tskip "ldiskfs only test"\n'
            '\tremote_mds_nodsh && skip "remote MDS with nodsh"\n'
            '\t(( MDS1_VERSION >= $(version_code 2.17.58) )) ||\n'
            '\t\tskip "Need MDS >= 2.17.58 for lfs find --local"\n'
            '\t[[ $(facet_active_host mds1) == $(facet_active_host ost1) ]] ||\n'
            '\t\tskip "mds1 and ost1 are not on one node"\n'
            '\n'
            '\tlocal scan_err=$TMP/$tfile.scanerr\n'
            '\n'
            '\tstack_trap "rm -f $scan_err"\n'
            '\tis_mounted $MOUNT || setup_noconfig\n'
            '\tcheck_mount || error "check_mount failed"\n'
            '\tcreatemany -o $DIR/$tfile- 10 || error "createmany failed"\n'
            '\n'
            '\t# a --local sweep with --ost or --mdt reads only targets of that type,\n'
            '\t# so where one node serves both it skips the other type\n'
            + dedent(inner) +
            '}\n'
            'run_test 300c "lfs find --local --ost or --mdt reads only that type"\n')

def split(v):
    zfs = 'export_zpool ost1' in v
    has_sweep = SWEEP_START in v
    a, ost = cut_if_block(v, OST_START)
    sweep = None
    if has_sweep:
        a, sweep = cut_if_block(a, SWEEP_START)
    if zfs:
        o = ('\t\tif zfs_scan_unbuilt $scan_err; then\n'
             '\t\t\techo "lfs has no zfs scan backend in this build"\n'
             '\t\telif ! grep -q "in use: pool imported" $scan_err; then\n')
        n = ('\t\tzfs_scan_unbuilt $scan_err &&\n'
             '\t\t\tskip "lfs has no zfs scan backend in this build"\n'
             '\t\tif ! grep -q "in use: pool imported" $scan_err; then\n')
        assert a.count(o) == 1
        a = a.replace(o, n)
    a = a.replace('\t# to answer; the sweep above runs only where mds1 and ost1 share a node.\n',
                  '\t# to answer; test_300c sweeps where mds1 and ost1 share a node.\n')
    a = a.replace('test_300() {\n', 'test_300a() {\n', 1).replace('\nrun_test 300 ', '\nrun_test 300a ', 1)
    out = a + '\n' + t300b(ost, zfs)
    if sweep is not None:
        out += '\n' + t300c(sweep)
    assert 'echo "not ' not in out and 'echo "lfs has no' not in out
    return out

def fn(path, s, subj):
    if path != P or 'test_300() {\n' not in s:
        return s
    i = s.index('test_300() {\n')
    j = s.index('\nrun_test 300 ', i)
    j = s.index('\n', j + 1) + 1
    return s[:i] + split(s[i:j]) + s[j:]
