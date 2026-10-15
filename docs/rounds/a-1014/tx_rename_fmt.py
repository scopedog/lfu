# Formatting after the sc_ -> lfsc_ rename: lines past 80 columns and the
# two struct fields whose names now reach the comment column.
R = [
 ("lustre/tests/llapi_scan_changelog_test.c",
  '\tASSERTF(got != 0, "lfsc_got came back 0; the scan answers for something");\n',
  '\tASSERTF(got != 0,\n\t\t"lfsc_got came back 0; the scan answers for something");\n'),
 ("lustre/utils/liblustreapi_scan_changelog.c",
  "\t * Off the copy, and only after lfsc_size: lfsc_mdtname sits at the end of\n"
  "\t * the minimum, so reading it off the caller's own struct first would\n"
  "\t * read past a struct too short to carry it -- the size check is what\n"
  "\t * establishes that it is there at all.\n",
  "\t * Off the copy, and only after lfsc_size: lfsc_mdtname sits at the end\n"
  "\t * of the minimum, so reading it off the caller's own struct first\n"
  "\t * would read past a struct too short to carry it -- the size check is\n"
  "\t * what establishes that it is there at all.\n"),
 ("lustre/utils/liblustreapi_scan_changelog.c",
  "\t\t*scl.lfsc_got = scl.lfsc_want != 0 ? (scl.lfsc_want & known) : known;\n",
  "\t\t*scl.lfsc_got = scl.lfsc_want != 0 ?\n\t\t\t\t(scl.lfsc_want & known) : known;\n"),
 ("lustre/utils/liblustreapi_scan_changelog.c",
  "\t\trc = llapi_changelog_start(&sl->sl_priv, flags, scl.lfsc_mdtname,\n\t\t\t\t\t   (long long)scl.lfsc_startrec);\n",
  "\t\trc = llapi_changelog_start(&sl->sl_priv, flags,\n\t\t\t\t\t   scl.lfsc_mdtname,\n\t\t\t\t\t   (long long)scl.lfsc_startrec);\n"),
 ("lustre/utils/liblustreapi_scan_changelog.c",
  "\tif (sl->sl_stop_rc == 0 && (scl.lfsc_flags & LLAPI_SCAN_CL_F_COALESCE)) {\n",
  "\tif (sl->sl_stop_rc == 0 &&\n\t    (scl.lfsc_flags & LLAPI_SCAN_CL_F_COALESCE)) {\n"),
 ("lustre/utils/lustreapi_internal.h",
  " * The same, for struct llapi_scan_changelog_param.  Its minimum reaches\n"
  " * through lfsc_mdtname, but lfsc_user, lfsc_mnt, lfsc_stats and lfsc_got are pointers\n"
  " * beyond it, so a size stopping inside one of them would leave it half the\n"
  " * caller's bytes and half zero -- and lfsc_user and lfsc_mnt are dereferenced\n"
  " * as strings.",
  " * The same, for struct llapi_scan_changelog_param.  Its minimum reaches\n"
  " * through lfsc_mdtname, but lfsc_user, lfsc_mnt, lfsc_stats and lfsc_got\n"
  " * are pointers beyond it, so a size stopping inside one of them would\n"
  " * leave it half the caller's bytes and half zero -- and lfsc_user and\n"
  " * lfsc_mnt are dereferenced as strings."),
 ("include/lustre/lustreapi.h",
  "\t__u64\t\t\t lfsc_type_mask;\t/* BIT(CL_*); 0: every type */\n",
  "\t/* BIT(CL_*); 0: every type */\n\t__u64\t\t\t lfsc_type_mask;\n"),
 ("include/lustre/lustreapi.h",
  "\t__u32\t\t\t lfsc_max_cached;\t/* objects held while\n\t\t\t\t\t\t * coalescing; 0 = the default\n\t\t\t\t\t\t */\n",
  "\t/* objects held while coalescing; 0 = the default */\n\t__u32\t\t\t lfsc_max_cached;\n"),
]
def fn(path, s, subj):
    for p, old, new in R:
        if p == path and old in s:
            assert s.count(old) == 1, (path, old[:40])
            s = s.replace(old, new)
    return s
