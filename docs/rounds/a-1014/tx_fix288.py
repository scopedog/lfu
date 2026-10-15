# lreview on 68288': an OST object gets its owner FID on its first write,
# setattr or punch, not at create; and a comment that gave the wrong reason.
R = {
'Documentation/man1/lfs-find.1': [(
 'nor does an OST object no file owns yet,\n',
 'nor does an OST object that has never been written to, even one\nbelonging to an empty file,\n')],
'Documentation/man3/llapi_scan_rec_path.3': [(
 'object is in this set only when no file owns it: a precreated object that has\n'
 'never been written carries no owner FID. Otherwise its FID resolves to the\n'
 'file that owns it.\n',
 'object is in this set when it has never been written to: the OST records its\n'
 'owner FID on the first write, setattr or punch, so a precreated object, and\n'
 'one belonging to a file created and never written, carry none. Otherwise its\n'
 'FID resolves to the file that owns it.\n')],
'lustre/utils/liblustreapi_scan.c': [(
 ' * has on the target.  An object no file owns yet -- precreated and never\n'
 ' * written, of which a target holds many -- has no owner and no name, and is\n',
 ' * has on the target.  An object never written to -- precreated, or part of\n'
 ' * a file created and never written -- has no owner and no name, and is\n')],
'lustre/utils/liblustreapi_pfind.c': [(
 '\t\t/* the mount point is copied into fds_mnt_path unbounded */\n',
 '\t\t/* the copies below are bounded: a longer one would be cut short */\n')],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
