# Move the striped-directory shard skip from 68288 down to 68159 (lreview on
# 68159'): the flag, its detection in the device gather, the masks, the skip
# in find_device_cb() and the man-page words.  Inserted, word for word as
# 68288 has them, into every tree that has llapi_find_device() but not yet
# the flag; 68288's own tree is left as it is.
DEF = '#define LLAPI_SCAN_LMV_SHARD\t0x0000800000000000ULL\n'
R = {
'include/lustre/lustreapi.h': [(
 '#define LLAPI_SCAN_LMV_FOREIGN\t0x0000002000000000ULL\n',
 '#define LLAPI_SCAN_LMV_FOREIGN\t0x0000002000000000ULL\n'
 '/*\n'
 ' * A striped directory\'s shard, whose trusted.lmv is LMV_MAGIC_STRIPE: an\n'
 ' * object with a linkea of its own -- name "<DFID>:<index>", parent the\n'
 ' * master -- that is not a directory the filesystem has a path for.  Set\n'
 ' * without LLAPI_SCAN_LMV, there being no lmv_user_md form of it, and only\n'
 ' * by a scan of a target: a namespace walk never sees a shard.  A consumer\n'
 ' * composing pathnames steps over it to the master, as mdt_path_current()\n'
 ' * does.\n'
 ' */\n' + DEF)],
'lustre/utils/liblustreapi_scan_device.c': [
 ('\tif (want & LLAPI_SCAN_LMV)\n\t\txa |= LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LMV);\n',
  '\tif (want & (LLAPI_SCAN_LMV | LLAPI_SCAN_LMV_SHARD))\n\t\txa |= LLAPI_SCAN_XA_BIT(LLAPI_SCAN_XA_LMV);\n'),
 ('/*\n * The master object of a striped directory: trusted.lmv holding an\n',
  '/*\n'
  ' * A striped directory\'s shard: its trusted.lmv is LMV_MAGIC_STRIPE, which\n'
  ' * scan_lmv_to_user() has no user form for and answers 0 to.  It is worth\n'
  ' * saying so anyway -- a shard has a linkea and looks like a directory to\n'
  ' * anything walking one, and it is not a directory the filesystem has a path\n'
  ' * for.\n'
  ' */\n'
  'static bool scan_lmv_is_shard(const void *disk, __u32 len)\n'
  '{\n'
  '\t__u32 magic;\n'
  '\n'
  '\tif (len < sizeof(magic))\n'
  '\t\treturn false;\n'
  '\n'
  '\tmemcpy(&magic, disk, sizeof(magic));\n'
  '\n'
  '\treturn __le32_to_cpu(magic) == LMV_MAGIC_STRIPE;\n'
  '}\n'
  '\n'
  '/*\n * The master object of a striped directory: trusted.lmv holding an\n'),
 ('\t\t\t\trec.lfsr_valid |= LLAPI_SCAN_LMV_FOREIGN;\n\t\t}\n\t}\n',
  '\t\t\t\trec.lfsr_valid |= LLAPI_SCAN_LMV_FOREIGN;\n'
  '\t\t} else if (scan_lmv_is_shard(val, len)) {\n'
  '\t\t\t/* no lfsr_lmv: there is no lmv_user_md for a shard.\n'
  '\t\t\t * The bit is the whole answer, and what a consumer\n'
  '\t\t\t * composing a pathname needs.\n'
  '\t\t\t */\n'
  '\t\t\trec.lfsr_valid |= LLAPI_SCAN_LMV_SHARD;\n'
  '\t\t}\n\t}\n'),
],
'lustre/utils/lustreapi_internal.h': [
 ('/* LLAPI_SCAN_LMV_FOREIGN describes lfsr_lmv, so asking for it asks for that */\n'
  'static inline __u64 scan_want_widen(__u64 want)\n{\n'
  '\tif (want & LLAPI_SCAN_LMV_FOREIGN)\n',
  '/* LMV_FOREIGN and LMV_SHARD are read from trusted.lmv, so both need LMV */\n'
  'static inline __u64 scan_want_widen(__u64 want)\n{\n'
  '\tif (want & (LLAPI_SCAN_LMV_FOREIGN | LLAPI_SCAN_LMV_SHARD))\n'),
 ('\t LLAPI_SCAN_LMV_FOREIGN |\t\t\t\t\\\n',
  '\t LLAPI_SCAN_LMV_FOREIGN | LLAPI_SCAN_LMV_SHARD |\t\t\\\n'),
 ('\t(LLAPI_SCAN_LAYOUT | LLAPI_SCAN_LMV | LLAPI_SCAN_LMV_FOREIGN |\t\\\n'
  '\t LLAPI_SCAN_HSM |\t\t\t\t\t\t\\\n',
  '\t(LLAPI_SCAN_LAYOUT | LLAPI_SCAN_LMV | LLAPI_SCAN_LMV_FOREIGN |\t\\\n'
  '\t LLAPI_SCAN_LMV_SHARD | LLAPI_SCAN_HSM |\t\t\t\\\n'),
],
'lustre/utils/liblustreapi_pfind.c': [
 ('\t\twant |= printf_format_want(param->fp_format_printf_str, NULL);\n\n\treturn want;\n}\n',
  '\t\twant |= printf_format_want(param->fp_format_printf_str, NULL);\n'
  '\t/* find_device_cb() skips a shard, so it has to know one */\n'
  '\twant |= LLAPI_SCAN_LMV_SHARD;\n\n\treturn want;\n}\n'),
 ('\tint checked_type = 0;\n\tint rc;\n\n\trc = find_device_prefilter(rec, param, &checked_type);\n',
  '\tint checked_type = 0;\n\tint rc;\n\n'
  '\t/* a shard is part of its striped directory: the master answers */\n'
  '\tif (rec->lfsr_valid & LLAPI_SCAN_LMV_SHARD)\n\t\treturn 0;\n\n'
  '\trc = find_device_prefilter(rec, param, &checked_type);\n'),
],
'Documentation/man3/llapi_scan_namespace.3': [
 ('.TP\n.B LLAPI_SCAN_MDT_INDEX\n',
  '.TP\n'
  '.B LLAPI_SCAN_LMV_SHARD\n'
  'The object is a striped directory\'s shard, whose\n'
  '.B trusted.lmv\n'
  'is\n'
  '.BR LMV_MAGIC_STRIPE .\n'
  'It carries no\n'
  '.I lfsr_lmv\n'
  '\\(em there is no\n'
  '.B lmv_user_md\n'
  'form of one \\(em so the bit is the whole answer. A shard has a linkea of its\n'
  'own, naming the master as its parent and itself\n'
  '.RI < DFID >: <index>,\n'
  'and is not a directory the filesystem has a pathname for, so a consumer\n'
  'composing pathnames steps through it to the master. Only\n'
  '.BR llapi_scan_device (3)\n'
  'reports it: a namespace walk never reaches a shard.\n'
  '.TP\n.B LLAPI_SCAN_MDT_INDEX\n')],
'Documentation/man3/llapi_find_device.3': [
 ('which object that is.\n.SH RETURN VALUES\n',
  'which object that is.\n.LP\n'
  'A striped directory has a shard on each MDT it is striped over. The shards are\n'
  'not reported: the master answers for the directory, once, as a walk does.\n'
  '.SH RETURN VALUES\n')],
}
def applies(path, s):
    return True
_state = {}
def fn(path, s, subj):
    # the gate is per tree: 68159' and above, before 68288
    return s
def tree_fn(files):
    """files: dict path->content for the whole commit; returns changed dict."""
    if 'lustre/utils/liblustreapi_pfind.c' not in files:
        return {}
    if 'int llapi_find_device(' not in files['lustre/utils/liblustreapi_pfind.c']:
        return {}
    if DEF in files.get('include/lustre/lustreapi.h', ''):
        return {}
    out = {}
    for p, reps in R.items():
        s = files[p]
        for old, new in reps:
            assert s.count(old) == 1, (p, old[:50], s.count(old))
            s = s.replace(old, new)
        out[p] = s
    return out
