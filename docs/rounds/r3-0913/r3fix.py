#!/usr/bin/env python3
"""Round 3 (2026-09-13) fixes as idempotent transforms over each commit's tree.

apply(tree_dir, name, msg) -> (msg, applied_ids, errors)
A transform applies wherever its old text is present, restricted by
`only` (commit names) or `since` (first commit name it may apply at).
"""
import os
import re

ORDER = ["c68094", "c68095", "c68156", "c68157", "c68158", "c68159",
         "c68160", "c68163", "c68288", "c68415", "c68416", "c68417",
         "c68418", "c68419", "c68420", "c68726", "c68727",
         "c68810", "c68811", "c68812", "c68813", "c68814", "c68815",
         "c68816", "c68817", "c68818"]

MSG = "<MSG>"
T = []


def t(tid, path, old, new, only=None, since=None, count_all=False):
    T.append(dict(id=tid, path=path, old=old, new=new, only=only,
                  since=since, all=count_all))


def f(tid, path, fn, only=None, since=None):
    T.append(dict(id=tid, path=path, fn=fn, only=only, since=since))


SANITY = "lustre/tests/sanity.sh"
PFIND = "lustre/utils/liblustreapi_pfind.c"
ZFS = "lustre/utils/libscan_zfs.c"
CL = "lustre/utils/liblustreapi_scan_changelog.c"
CLT = "lustre/tests/llapi_scan_changelog_test.c"
FIND1 = "Documentation/man1/lfs-find.1"

# ---------------------------------------------------------------- 68094
t("77aea866", SANITY,
  "\t# the binary this test runs is built by the same change that adds the\n"
  "\t# API, so its presence is the gate; a version number cannot be one\n"
  "\t# while master reports the version the change is landing into\n"
  "\t[[ -x $LUSTRE/tests/llapi_scan_test ]] ||\n"
  "\t\tskip \"llapi_scan_test is not built\"\n"
  "\n"
  "\tmkdir_on_mdt0 $DIR/$tdir\n",
  "\t(( CLIENT_VERSION >= $(version_code 2.17.57) )) ||\n"
  "\t\tskip \"Need client >= 2.17.57 for llapi_scan_namespace()\"\n"
  "\n"
  "\t# any MDT: nothing here depends on which one holds the tree\n"
  "\t$LFS mkdir -i $((RANDOM % MDSCOUNT)) $DIR/$tdir ||\n"
  "\t\terror \"mkdir $tdir failed\"\n")
t("77aea866-157d", SANITY,
  "\t# as 157c: the binary ships with the API, so its presence is the gate\n"
  "\t[[ -x $LUSTRE/tests/llapi_scan_changelog_test ]] ||\n"
  "\t\tskip \"llapi_scan_changelog_test is not built\"\n",
  "\t(( CLIENT_VERSION >= $(version_code 2.17.57) )) ||\n"
  "\t\tskip \"Need client >= 2.17.57 for llapi_scan_changelog()\"\n")

# ---------------------------------------------------------------- 68160
t("6379d8eb", "lustre/tests/conf-sanity.sh",
  " ${sdir:+--search $sdir}", "", only={"c68160"}, count_all=True)

# ---------------------------------------------------------------- 68163
t("4fe322a2", MSG,
  "what the ZFS backend takes, and never reaches the stat.  So\n"
  "scan_backend_kind() needs no slash case of its own, and -ENOTSUP\n"
  "keeps the meaning llapi_scan_device.3 gives it and conf-sanity 300\n"
  "keys its skip on: this build has no backend for the target.\n",
  "what the ZFS backend takes, and never reaches the stat.\n"
  "scan_backend_kind() tests the slash first as well, before its own\n"
  "stat(), so a mount point or any other directory is never sent to the\n"
  "ZFS backend.  -ENOTSUP keeps the meaning llapi_scan_device.3 gives it\n"
  "and conf-sanity 300 keys its skip on: this build has no backend for\n"
  "the target.\n")
t("a3ac0b0d", ZFS,
  "\tif (zap_lookup(t->zt_os, MASTER_NODE_OBJ, ZFS_UNLINKED_SET, 8, 1,\n"
  "\t\t       &t->zt_unlinked) != 0)\n"
  "\t\tt->zt_unlinked = 0;\n",
  "\tif (zap_lookup(t->zt_os, MASTER_NODE_OBJ, ZFS_UNLINKED_SET, 8, 1,\n"
  "\t\t       &t->zt_unlinked) != 0)\n"
  "\t\tt->zt_unlinked = 0;\n"
  "\t/* empty once drained, as on a clean stop: skip the per-object lookup */\n"
  "\tif (t->zt_unlinked != 0) {\n"
  "\t\tuint64_t n;\n"
  "\n"
  "\t\tif (zap_count(t->zt_os, t->zt_unlinked, &n) == 0 && n == 0)\n"
  "\t\t\tt->zt_unlinked = 0;\n"
  "\t}\n")
t("2cdfde78-fn", ZFS,
  "\t       ((pflags & ZFS_APPENDONLY) ? STATX_ATTR_APPEND : 0) |\n"
  "\t       ((pflags & ZFS_NODUMP) ? STATX_ATTR_NODUMP : 0);\n",
  "\t       ((pflags & ZFS_APPENDONLY) ? STATX_ATTR_APPEND : 0);\n")
t("2cdfde78-cmt", ZFS,
  "/* z_pflags bits are ZFS's own; only these three have STATX_ATTR_*\n"
  " * equivalents.  Per-file compressed or encrypted does not exist on ZFS --\n"
  " * both are dataset properties -- so those bits are never set, rather than\n"
  " * set wrong.\n"
  " */\n",
  "/* z_pflags bits are ZFS's own; IMMUTABLE and APPEND are the two a namespace\n"
  " * scan also reports.  ZFS_NODUMP is left out for the reason\n"
  " * libscan_ldiskfs.c gives.  Per-file compressed or encrypted does not exist\n"
  " * on ZFS -- both are dataset properties.\n"
  " */\n")
t("2cdfde78-mask", ZFS,
  "\t\tobj.so_attrs_mask = STATX_ATTR_IMMUTABLE | STATX_ATTR_APPEND |\n"
  "\t\t\t\t    STATX_ATTR_NODUMP;\n",
  "\t\tobj.so_attrs_mask = STATX_ATTR_IMMUTABLE | STATX_ATTR_APPEND;\n")
t("2cdfde78-hdr", "lustre/utils/lustreapi_scan_backend.h",
  "\t * two backends do not support the same set -- ldiskfs reports\n"
  "\t * ENCRYPTED and ZFS reports NODUMP -- so one constant in the scanner\n"
  "\t * would either over-claim for one or drop a bit the other found.\n",
  "\t * two backends do not support the same set -- ldiskfs reports\n"
  "\t * ENCRYPTED, which ZFS has no per-file form of -- so one constant in\n"
  "\t * the scanner would over-claim for one of them.\n")
t("2cdfde78-man", "Documentation/man3/llapi_scan_device.3",
  "gets from the client. The ZFS backend declares\n"
  ".B STATX_ATTR_NODUMP\n"
  "in place of\n"
  ".BR STATX_ATTR_ENCRYPTED :\n",
  "gets from the client. The ZFS backend declares only\n"
  ".B STATX_ATTR_IMMUTABLE\n"
  "and\n"
  ".BR STATX_ATTR_APPEND :\n")

# ---------------------------------------------------------------- 68288
t("cb25d398-a", MSG,
  "MDT FID, and the stripe index filter_fid keeps in its f_ver is\n"
  "dropped,\n"
  "that field being an index",
  "MDT FID, and the stripe index filter_fid keeps in its f_ver is dropped,\n"
  "that field being an index")
t("cb25d398-b", MSG,
  "once the map is in use.  The map\n"
  "is\n"
  "used precisely",
  "once the map is in use.  The map is\n"
  "used precisely")
t("cb25d398-c", MSG,
  "exports its pool where the backend\n"
  "is\n"
  "ZFS, and compares",
  "exports its pool where the backend is\n"
  "ZFS, and compares")
t("cb25d398-d", MSG,
  "merely created, a precreated object\n"
  "being\n"
  "rightly nameless.",
  "merely created, a precreated object being\n"
  "rightly nameless.")
t("cb25d398-e", MSG,
  "conf-sanity test_303 covers --paths, where 301 and\n"
  "302 both exercise only --fid2path, so the composition --paths exists\n"
  "for was never run.  It scans an MDT in service with no mount given,\n"
  "which is the case a filesystem whose only MDT is the target has to be\n"
  "named in, and asserts the answer is the client's set: one path per\n"
  "object rather than one per name, the hardlinked object once, no FID\n"
  "where a path was asked for, and no mount point in the answer -- root-\n"
  "relative being what separates it from --fid2path, and a mounted prefix\n"
  "meaning the wrong composer ran.  It also asserts the two refusals:\n"
  "--paths on an OST, whose objects are named by files that live on an\n"
  "MDT, and --paths together with --fid2path.  ldiskfs only, an imported\n"
  "ZFS pool answering EBUSY by design.\n",
  "conf-sanity test_303 covers --paths, where 301 and 302 both exercise\n"
  "only --fid2path, so the composition --paths exists for was never run.\n"
  "It scans an MDT in service with no mount given, which is the case a\n"
  "filesystem whose only MDT is the target has to be named in, and\n"
  "asserts the answer is the client's set: one path per object rather\n"
  "than one per name, the hardlinked object once, no FID where a path was\n"
  "asked for, and no mount point in the answer -- root-relative being\n"
  "what separates it from --fid2path, and a mounted prefix meaning the\n"
  "wrong composer ran.  It also asserts the two refusals: --paths on an\n"
  "OST, whose objects are named by files that live on an MDT, and --paths\n"
  "together with --fid2path.  ldiskfs only, an imported ZFS pool\n"
  "answering EBUSY by design.\n")
t("msg-backslash", MSG,
  "The EXAMPLES fragment in llapi_scan_rec_path.3 escapes its newline as\n"
  "n, not n: troff reads the single form as a register reference,\n"
  "which rendered the line as printf(\"%s0, path).",
  "The EXAMPLES fragment in llapi_scan_rec_path.3 escapes the backslash\n"
  "of its newline escape: troff reads a single one as its own escape,\n"
  "which rendered the line as printf(\"%s0, path).")
t("ede43c98", "Documentation/man3/llapi_scan_rec_path.3",
  "whose FID has no FLD range, or a FID the MDT no longer resolves. An OST data\n"
  "object is not in this set: its FID resolves to the file that owns it.\n",
  "whose FID has no FLD range, or a FID the MDT no longer resolves. An OST data\n"
  "object is in this set only when no file owns it: a precreated object that has\n"
  "never been written carries no owner FID. Otherwise its FID resolves to the\n"
  "file that owns it.\n")
t("ae6a9326", "include/lustre/lustreapi.h",
  "#define LLAPI_SCAN_LMV_SHARD\t0x0020000000000000ULL",
  "#define LLAPI_SCAN_LMV_SHARD\t0x0000800000000000ULL")
t("4e556ce9", PFIND,
  "\tchar mfs[MAX_OBD_NAME + 1] = { 0 };\n",
  "\tchar mfs[PATH_MAX] = { 0 };\n")

# ---------------------------------------------------------------- 68415
t("bfa7b47a", "include/lustre/lustreapi.h",
  " * lfsr_name, lfsr_lmm, lfsr_lmv, lfsr_linkea, lfsr_src_name and\n"
  " * lfsr_jobid point into\n"
  " * scanner-owned memory and must be copied by a consumer that keeps them.\n",
  " * lfsr_name, lfsr_lmm, lfsr_lmv, lfsr_linkea, lfsr_src_name and\n"
  " * lfsr_jobid point into scanner-owned memory and must be copied by a\n"
  " * consumer that keeps them.\n")
t("b3c1e9ac", CLT,
  "\tsc.sc_flags = LLAPI_SCAN_CL_F_ONCE;\n"
  "\trc = llapi_scan_changelog(&sc, cl_cb, &res);\n"
  "\tASSERTF(rc == -EINVAL, \"_ONCE without _COALESCE returned %d\", rc);\n"
  "\n"
  "\tllapi_msg_set_level(LLAPI_MSG_ERROR);\n"
  "\n"
  "\tprintf(\"  eight bad calls refused with -EINVAL\\n\");\n",
  "\tsc.sc_flags = LLAPI_SCAN_CL_F_ONCE;\n"
  "\trc = llapi_scan_changelog(&sc, cl_cb, &res);\n"
  "\tASSERTF(rc == -EINVAL, \"_ONCE without _COALESCE returned %d\", rc);\n"
  "\n"
  "\tparam_init(&sc);\n"
  "\tsc.sc_type_mask = 1ULL << CL_UNLINK;\n"
  "\tsc.sc_user = NULL;\n"
  "\trc = llapi_scan_changelog(&sc, cl_cb, &res);\n"
  "\tASSERTF(rc == -EINVAL, \"a type mask without a user returned %d\", rc);\n"
  "\n"
  "\tllapi_msg_set_level(LLAPI_MSG_ERROR);\n"
  "\n"
  "\tprintf(\"  nine bad calls refused with -EINVAL\\n\");\n")
t("e156feaf", CLT,
  "\t       \"       -o  tests to run\\n\", prog);\n"
  "\texit(0);\n",
  "\t       \"       -o  tests to run\\n\", prog);\n"
  "\texit(EXIT_FAILURE);\n")
t("aa575ca1", CL,
  "\t\t\t\t LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS)\n",
  "\t\t\t\t LLAPI_SCAN_SIZE | LLAPI_SCAN_BLOCKS | \\\n"
  "\t\t\t\t LLAPI_SCAN_LAZY_SIZE | LLAPI_SCAN_LAZY_BLOCKS)\n")
t("aa575ca1-msg", MSG,
  "OBD_MD_FLLAZYSIZE, so they are not interchangeable.\n",
  "OBD_MD_FLLAZYSIZE, so they are not interchangeable.  sc_got counts\n"
  "them under a resolve, as both siblings' masks do.\n")

RESOLVE_OLD = (
    "/*\n"
    " * Fill what the changelog does not carry, from the object itself.\n"
    " *\n"
    " * This is one open and one stat per object -- two of each for a regular\n"
    " * file whose demand mask named a size, the glimpse needing its own open --\n"
    " * which is why it is opt-in and why\n"
    " * object mode exists: a file written a hundred times is one lookup here, not\n"
    " * a hundred.  An object that has since been unlinked cannot be opened, and\n"
    " * that is not an error -- the record is delivered with what the event said\n"
    " * and the rest absent, and a predicate that needed more counts undecided.\n"
    " */\n")
RESOLVE_NEW = (
    "/*\n"
    " * Fill what the changelog does not carry, from the object itself.\n"
    " *\n"
    " * This is one open and one stat per object -- two of each for a regular\n"
    " * file whose demand mask named a size, the glimpse needing its own open --\n"
    " * which is why it is opt-in and why object mode exists: a file written a\n"
    " * hundred times is one lookup here, not a hundred.  An object that has since\n"
    " * been unlinked cannot be opened, and that is not an error -- the record is\n"
    " * delivered with what the event said and the rest absent, and a predicate\n"
    " * that needed more counts undecided.\n"
    " */\n")
RESOLVE_FN = "static void scan_cl_resolve(struct scan_cl *sl, struct llapi_scan_rec *rec)\n{\n"


def move_resolve_comment(text):
    if RESOLVE_OLD not in text or RESOLVE_FN not in text:
        return text, False
    text = text.replace(RESOLVE_OLD, "", 1)
    text = text.replace(RESOLVE_FN, RESOLVE_NEW + RESOLVE_FN, 1)
    return text, True


f("617400ed", CL, move_resolve_comment)
t("617400ed-wrap", CL,
  "\t * does -- but only a regular file has that size, and llite gives a\n"
  "\t * special file\n"
  "\t * init_special_inode(), so a real open on a device node stored in\n"
  "\t * the filesystem opens the driver.  O_NONBLOCK holds off the wait,\n"
  "\t * not the rest of what an open does.\n",
  "\t * does -- but only a regular file has that size, and llite gives a\n"
  "\t * special file init_special_inode(), so a real open on a device node\n"
  "\t * stored in the filesystem opens the driver.  O_NONBLOCK holds off the\n"
  "\t * wait, not the rest of what an open does.\n")

# ---------------------------------------------------------------- 68416
t("adac49ea-a", MSG,
  "The kernel-doc no longer lists lfsp_flags among the fields that are\n"
  "ignored.  Every flag it defines is, but a bit outside them is refused\n"
  "with -EINVAL, as the code does and llapi_scan_fid.3 already says.\n",
  "The flags the other scanners define are ignored here, but a bit\n"
  "outside them is refused with -EINVAL, as llapi_scan_fid.3 says.\n")
t("adac49ea-b", MSG,
  "mnt_fd has to be the mount root now.  The ioctl behind\n"
  "llapi_fid2path_at() takes any descriptor in the filesystem, and the\n"
  "page always named llapi_root_path_open(), which returns the root; a\n"
  "caller that passed something else answered before and answers -ENOENT\n"
  "now.  mnt_path stays required and stays what lfsr_path is built from,\n"
  "so a wrong one still mislabels the answer -- it just no longer decides\n"
  "what was read.\n",
  "mnt_fd has to be the mount root, as llapi_root_path_open() returns:\n"
  "the ioctl behind llapi_fid2path_at() takes any descriptor in the\n"
  "filesystem, but the name it answers is relative to the root, so any\n"
  "other descriptor answers -ENOENT.  mnt_path is required and is what\n"
  "lfsr_path is built from, so a wrong one mislabels the answer.\n")
t("afc96fd0-msg", MSG,
  "The syscalls go through mnt_fd, not through the composed pathname.\n"
  "The FID was already resolved through that descriptor; the statx, the\n"
  "object's open and the parent's now use it too, at the name fid2path\n"
  "answered, so mnt_fd alone says which filesystem is read.  An fd pins\n"
  "its mount where a path string is resolved afresh every time, and a\n"
  "mount replaced between the open and the scan would otherwise have the\n"
  "resolve read one filesystem and the gather another, with rc 0 and\n"
  "nothing said.  It also takes the mount prefix off every lookup, three\n"
  "per object, which over a changelog's worth of FIDs is what this entry\n"
  "point is for.\n",
  "The call's own syscalls go through mnt_fd, not through the composed\n"
  "pathname.  The FID was already resolved through that descriptor; the\n"
  "statx and the open of the parent, or of a directory itself, use it\n"
  "too, at the name fid2path answered.  An fd pins its mount where a path\n"
  "string is resolved afresh every time.  The opens scan_rec_gather()\n"
  "makes for LLAPI_SCAN_PROJID, LLAPI_SCAN_HSM and a regular file's\n"
  "LLAPI_SCAN_MDT_INDEX are still by pathname, so for those three\n"
  "mnt_path does decide what is read.  It also takes the mount prefix\n"
  "off the call's own lookups, which over a changelog's worth of FIDs is\n"
  "what this entry point is for.\n")
t("afc96fd0-doc", "lustre/utils/liblustreapi_scan.c",
  " * @mnt_fd is the filesystem and @mnt_path only the spelling.  Every syscall\n"
  " * here -- the statx, the object's open, the parent's -- goes through @mnt_fd\n"
  " * and the name fid2path answered, so the two cannot name different\n"
  " * filesystems between them: an fd pins its mount, where a path string is\n"
  " * resolved afresh each time and can be a mount that has since been replaced.\n",
  " * @mnt_fd is the filesystem and @mnt_path mostly the spelling.  The syscalls\n"
  " * this function makes -- the statx, and the open of a directory or of the\n"
  " * parent -- go through @mnt_fd and the name fid2path answered: an fd pins its\n"
  " * mount, where a path string is resolved afresh each time and can be a mount\n"
  " * that has since been replaced.  scan_rec_gather() still opens by pathname\n"
  " * for LLAPI_SCAN_PROJID, LLAPI_SCAN_HSM and a regular file's\n"
  " * LLAPI_SCAN_MDT_INDEX, so for those @mnt_path does decide what is read.\n")
t("afc96fd0-doc2", "lustre/utils/liblustreapi_scan.c",
  " * what the record's lfsr_path is built from, so a wrong one still mislabels\n"
  " * the answer -- it just no longer decides what was read.\n",
  " * what the record's lfsr_path is built from, so a wrong one mislabels the\n"
  " * answer.\n")
t("afc96fd0-man", "Documentation/man3/llapi_scan_fid.3",
  "returns. It is the filesystem: the FID is resolved through it, and the object\n"
  "and its parent are opened through it too, at the name\n"
  ".BR llapi_fid2path (3)\n"
  "answered. The root, rather than any descriptor in the filesystem, because that\n"
  "name is relative to it.\n",
  "returns. It is the filesystem: the FID is resolved through it, and a directory,\n"
  "or the parent of anything else, is opened through it too, at the name\n"
  ".BR llapi_fid2path (3)\n"
  "answered. The root, rather than any descriptor in the filesystem, because that\n"
  "name is relative to it. The opens that gather a project id, HSM state and a\n"
  "regular file's MDT index are still made by pathname, through\n"
  ".IR mnt_path .\n")
t("afc96fd0-man2", "Documentation/man3/llapi_scan_fid.3",
  "is open on mislabels the answer; it no longer decides what was read. That is\n",
  "is open on mislabels the answer. That is\n")
t("00ea7018", PFIND,
  " * Four fields are the search's to decide and are overwritten whatever the\n"
  " * caller set: lfsp_want (the predicates decide it), lfsp_thread_count,\n"
  " * lfsp_stats\n"
  " * and lfsp_filter.  lfsp_filter goes because this function has no void *data of\n"
  " * its own to give it: the scan carries find's state, and a caller's callback\n"
  " * would be handed that and read it as its own context.\n",
  " * Five fields are the search's to decide and are overwritten whatever the\n"
  " * caller set: lfsp_want (the predicates decide it), lfsp_thread_count,\n"
  " * lfsp_stats, lfsp_filter and lfsp_got.  lfsp_filter goes because this\n"
  " * function has no void *data of its own to give it: the scan carries find's\n"
  " * state, and a caller's callback would be handed that and read it as its own\n"
  " * context.\n", since="c68416")
t("00ea7018-lower", PFIND,
  " * Four fields are the search's to decide and are overwritten whatever the\n"
  " * caller set: lfsp_want (the predicates decide it), lfsp_thread_count,\n"
  " * lfsp_stats\n"
  " * and lfsp_filter.  lfsp_filter goes because this function has no void *data of\n"
  " * its own to give it: the scan carries find's state, and a caller's callback\n"
  " * would be handed that and read it as its own context.\n",
  " * Four fields are the search's to decide and are overwritten whatever the\n"
  " * caller set: lfsp_want (the predicates decide it), lfsp_thread_count,\n"
  " * lfsp_stats and lfsp_filter.  lfsp_filter goes because this function has\n"
  " * no void *data of its own to give it: the scan carries find's state, and a\n"
  " * caller's callback would be handed that and read it as its own context.\n",
  only=set(ORDER[:ORDER.index("c68416")]))
t("1f5eb08c-decl", "lustre/tests/llapi_scan_test.c",
  "\tchar mnt[PATH_MAX], want[PATH_MAX], copy[PATH_MAX];\n"
  "\tstruct fid_seen fs;\n",
  "\tchar mnt[PATH_MAX], want[PATH_MAX], copy[PATH_MAX];\n"
  "\tchar slashed[PATH_MAX + 1];\n"
  "\tstruct fid_seen fs;\n")
t("1f5eb08c", "lustre/tests/llapi_scan_test.c",
  "\tASSERTF((fs.fs_valid & LLAPI_SCAN_FID) != 0,\n"
  "\t\t\"the record carries no FID: lfsr_valid %#llx\",\n"
  "\t\t(unsigned long long)fs.fs_valid);\n"
  "\n"
  "\t/* a filter that skips",
  "\tASSERTF((fs.fs_valid & LLAPI_SCAN_FID) != 0,\n"
  "\t\t\"the record carries no FID: lfsr_valid %#llx\",\n"
  "\t\t(unsigned long long)fs.fs_valid);\n"
  "\n"
  "\t/* a trailing slash on mnt_path is trimmed, not doubled into the path */\n"
  "\trc = snprintf(slashed, sizeof(slashed), \"%s/\", mnt);\n"
  "\tASSERTF(rc > 0 && (size_t)rc < sizeof(slashed), \"path too long\");\n"
  "\tmemset(&fs, 0, sizeof(fs));\n"
  "\trc = llapi_scan_fid(mnt_fd, slashed, &fid, &sp, fid_cb, &fs);\n"
  "\tASSERTF(rc == 0, \"llapi_scan_fid under '%s' failed: %s\", slashed,\n"
  "\t\tstrerror(-rc));\n"
  "\tASSERTF(strcmp(fs.fs_path, want) == 0,\n"
  "\t\t\"lfsr_path under '%s' is '%s', expected '%s'\", slashed,\n"
  "\t\tfs.fs_path, want);\n"
  "\tASSERTF(strcmp(fs.fs_name, basename(copy)) == 0,\n"
  "\t\t\"lfsr_name under '%s' is '%s', expected '%s'\", slashed,\n"
  "\t\tfs.fs_name, basename(copy));\n"
  "\n"
  "\t/* a filter that skips")

# ---------------------------------------------------------------- 68417
SYN_SIZE = ".RB [[ ! ]\n.BR --size | -s\n"
SYN_SINCE = ".RB [ --since\n"
SYN_END = ".RB [[ ! ]\n.BR --stripe-count | -c\n"
OPT_SIZE = ".TP\n.BR -s \", \" --size\n"
OPT_SINCE = ".TP\n.BI --since \" TIME\""
OPT_END = ".TP\n.BR -k \", \" --skip\n"


def _move(text, anchor, start, end):
    a = text.find(anchor)
    s = text.find(start)
    if a < 0 or s < 0 or s < a:
        return text, False
    e = text.find(end, s)
    if e < 0:
        raise RuntimeError("no end for " + start)
    block = text[s:e]
    text = text[:s] + text[e:]
    return text[:a] + block + text[a:], True


def move_since(text):
    text, a = _move(text, SYN_SIZE, SYN_SINCE, SYN_END)
    text, b = _move(text, OPT_SIZE, OPT_SINCE, OPT_END)
    return text, a or b


f("a2ba1626", FIND1, move_since)
t("fff5372a-man", "Documentation/man3/llapi_find_since.3",
  ".I fp_thread_count\n"
  "is above 1. This source is single-threaded, and it is the first thing\n"
  "tested \\(em before\n"
  ".IR path ,\n"
  "the mount and the MDT list \\(em so a\n"
  ".B find_param\n"
  "that a walk left a thread count in is refused whatever else it holds.\n",
  ".I fp_thread_count\n"
  "is above 1. This source is single-threaded, and the count is tested as soon\n"
  "as the arguments are well formed \\(em before\n"
  ".I path\n"
  "is resolved or any MDT is read \\(em so a\n"
  ".B find_param\n"
  "that a walk left a thread count in is refused rather than run on one thread.\n")
t("fff5372a-dup", "Documentation/man3/llapi_find_since.3",
  ".IP\n"
  "Also for\n"
  ".I fp_thread_count\n"
  "above 1. This source is single-threaded, and it is the first thing tested\n"
  "\\(em before\n"
  ".IR path ,\n"
  "the mount and the MDT list \\(em so a\n"
  ".B find_param\n"
  "that a walk left a thread count in is refused whatever else it holds.\n",
  "")
t("fff5372a-msg", MSG,
  "llapi_find_since() refuses fp_thread_count above 1 for itself, before\n"
  "it looks at anything else: this source reads one MDT's changelog at a\n"
  "time and has no work to divide.  That is why lfs_find() now computes\n"
  "the default thread count on the walk's arm of the dispatch rather than\n"
  "above it -- computed for every search, the default alone was above 1\n"
  "and the refusal fired on every --since run, which is not a setting the\n"
  "caller made.\n",
  "llapi_find_since() refuses fp_thread_count above 1 for itself, once\n"
  "its arguments are well formed and before any MDT is read: this source\n"
  "reads one MDT's changelog at a time and has no work to divide.  So\n"
  "lfs_find() computes the default thread count on the walk's arm of the\n"
  "dispatch rather than above it -- computed for every search, the\n"
  "default alone is above 1 and the refusal would fire on every --since\n"
  "run, which is not a setting the caller made.\n")
t("fd5bc71b", PFIND,
  "\trc = llapi_get_obd_count(mnt_path, &mdt_bound, 1);\n"
  "\tif (rc < 0 || mdt_bound <= 0)\n"
  "\t\tmdt_bound = 1;\n",
  "\trc = llapi_get_obd_count(mnt_path, &mdt_bound, 1);\n"
  "\tif (rc < 0) {\n"
  "\t\tllapi_error(LLAPI_MSG_ERROR, rc,\n"
  "\t\t\t    \"cannot count the MDTs of '%s'\", mnt_path);\n"
  "\t\treturn rc;\n"
  "\t}\n"
  "\tif (mdt_bound <= 0)\n"
  "\t\tmdt_bound = 1;\n")
t("fd5bc71b-msg", MSG,
  "bound and each index confirmed with llapi_search_tgt() before its\n"
  "changelog is read.\n",
  "bound and each index confirmed with llapi_search_tgt() before its\n"
  "changelog is read.  A count that cannot be read at all is an error\n"
  "rather than a bound of one, which would search MDT0000 alone and say\n"
  "nothing.\n")
t("37d1fed2", PFIND,
  "\t\t\t    \"%llu objects could not be decided from their changelog record\",\n",
  "\t\t\t    \"%llu objects could not be decided and are not in the answer\",\n")
t("080e9b9d", "lustre/utils/lfs_find_parse.c",
  "\t\tif (strncmp(fmts[i], \"%H\", 2) == 0) {\n"
  "\t\t\tlocaltime_r(&now, &tm);\n"
  "\t\t} else {\n",
  "\t\tif (strncmp(fmts[i], \"%H\", 2) == 0) {\n"
  "\t\t\tlocaltime_r(&now, &tm);\n"
  "\t\t\ttm.tm_sec = 0;\t/* \"%H:%M\" sets no seconds */\n"
  "\t\t} else {\n")

# --threads refusal: name what reaches it at each commit
t("09cfc4b1-2a3e", PFIND,
  "--threads describes a walk; --since reads one changelog per MDT in turn",
  "--threads describes a walk; --since and --changelog read one changelog per MDT in turn",
  only={"c68418"})
t("09cfc4b1", PFIND,
  "--threads describes a walk; --since reads one changelog per MDT in turn",
  "--threads describes a walk; --since, --since-cookie and --changelog read one changelog per MDT in turn",
  since="c68419")

# ---------------------------------------------------------------- 68418
t("2d0b68e4", MSG,
  "object.  An object time is refused outright, a record carrying an\n"
  "event time and the two being different questions; the message says\n"
  "--since 1d is how to ask.  Only --mdt, --maxdepth and --mindepth are\n"
  "refused at every setting -- they describe a walk, or need something a\n"
  "per-MDT log does not have.  --ost and the object times are refused\n"
  "without --resolve alone, the lookup supplying both.\n",
  "object.  An object time is refused without --resolve, a record\n"
  "carrying an event time and the two being different questions; the\n"
  "message says --since 1d is how to ask.  Only --mdt, --maxdepth and\n"
  "--mindepth are refused at every setting -- they describe a walk, or\n"
  "need something a per-MDT log does not have.  --ost is refused without\n"
  "--resolve too, the lookup supplying it.\n")
t("b3d55630", FIND1,
  "counted as undecided rather than answered from the record's zeroes. So\n"
  ".B \\-\\-resolve\n"
  "can leave an object out that the same search without it reports by FID.\n",
  "counted as undecided rather than answered from the record's zeroes.\n")
t("3b37662f", "include/lustre/lustreapi.h",
  "\t\t\t\t fp_unused_bit3:1,  /* once used, we must add */\n"
  "\t\t\t\t fp_unused_bit4:1,  /* a separate flag field  */\n"
  "\t\t\t\t fp_unused_bits2:22; /* at the end of this    */\n",
  "\t\t\t\t fp_unused_bit3:1,  /* once used, we must add */\n"
  "\t\t\t\t fp_unused_bit4:1,  /* a flag field at the */\n"
  "\t\t\t\t fp_unused_bits2:22; /* end of this struct */\n")
t("195af7cb", PFIND,
  "\t * mark rather than passing that value off as a FID, so the gate below\n"
  "\t * would drop it -- but as an object whose name could not be\n"
  "\t * recovered, which a mark is not.  Testing the type here says which\n"
  "\t * case it is.\n",
  "\t * mark rather than passing that value off as a FID, so the gate below\n"
  "\t * drops it too; testing the type here keeps that from resting on the\n"
  "\t * library alone.\n")
t("195af7cb-msg", MSG,
  "with cr_tfid, so cr_tfid.f_seq would read back as CLM_ON|CLM_START,\n"
  "0x10001 -- and fid_seq_is_igif() accepts anything in [12, 0xffffffff],\n"
  "so the FID gate would pass a value that is not a FID and find_decide()\n"
  "would print it as a FID with no pathname.\n",
  "with cr_tfid, so cr_tfid.f_seq would read back as CLM_ON|CLM_START,\n"
  "0x10001, which fid_seq_is_igif() accepts.  llapi_scan_changelog()\n"
  "already clears LLAPI_SCAN_FID for a mark, so the FID gate drops it;\n"
  "the type test is defence in depth over that.\n")
t("37d1fed2-msg", MSG,
  "The undecided warning no longer claims a missing field.\n"
  "find_since_cand_cb() also counts an object undecided when it has gone\n"
  "and the search needed a lookup or named a subtree, and there the\n"
  "record answered -- the object is what is missing.  \"could not be\n"
  "decided from their changelog record\" covers both.\n",
  "The undecided warning names no cause.  find_since_cand_cb() counts an\n"
  "object undecided when its record cannot answer, and also when it has\n"
  "gone and the search needed a lookup or named a subtree, where the\n"
  "record did answer and the object is what is missing.\n")

# ---------------------------------------------------------------- 68419
COOKIE_TMP_FN = (
    "/*\n"
    " * The temporary a cookie is written through, beside it and private to this\n"
    " * run: two runs over one cookie -- a cron job that outlasts its interval --\n"
    " * must not truncate or unlink each other's copy between write and rename.\n"
    " * O_EXCL rather than mkstemp(), which would give a first run's cookie 0600\n"
    " * instead of the umask's answer.\n"
    " *\n"
    " * Return: an open descriptor, or a negative errno.\n"
    " */\n"
    "static int find_cookie_tmp(const char *file, char *tmp, size_t len)\n"
    "{\n"
    "\tint i;\n"
    "\n"
    "\tfor (i = 0; i < 100; i++) {\n"
    "\t\tint fd;\n"
    "\n"
    "\t\tif (snprintf(tmp, len, \"%s.%d.%d.new\", file, (int)getpid(),\n"
    "\t\t\t     i) >= (int)len)\n"
    "\t\t\treturn -ENAMETOOLONG;\n"
    "\t\tfd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0666);\n"
    "\t\tif (fd >= 0)\n"
    "\t\t\treturn fd;\n"
    "\t\tif (errno != EEXIST)\n"
    "\t\t\treturn -errno;\n"
    "\t}\n"
    "\n"
    "\treturn -EEXIST;\n"
    "}\n"
    "\n")
WRITE_HDR = (
    "static int find_cookie_write(const char *file, const char *fsname,\n"
    "\t\t\t     const char *root, const __u64 *seen, int nseen)\n")
# the kernel-doc above find_cookie_write() ends with this line
WRITE_DOC_TAIL = " * in place for the MDTs this run reached.\n */\n"


def add_cookie_tmp(text):
    if "static int find_cookie_tmp(" in text:
        return text, False
    anchor = WRITE_DOC_TAIL + WRITE_HDR
    if anchor not in text:
        return text, False
    # before find_cookie_write()'s own kernel-doc
    i = text.index(anchor)
    j = text.rfind("\n/*\n", 0, i)
    if j < 0:
        raise RuntimeError("no kernel-doc start for find_cookie_write")
    return text[:j + 1] + COOKIE_TMP_FN + text[j + 1:], True


f("e31be789-fn", PFIND, add_cookie_tmp, since="c68419")
t("e31be789-write", PFIND,
  "\tFILE *fp;\n"
  "\tint rc = 0;\n"
  "\tint i;\n"
  "\n"
  "\tif (snprintf(tmp, sizeof(tmp), \"%s.new\", file) >= (int)sizeof(tmp))\n"
  "\t\treturn -ENAMETOOLONG;\n"
  "\n"
  "\trc = find_ck_escape(rootesc, sizeof(rootesc), root);\n"
  "\tif (rc != 0)\n"
  "\t\treturn rc;\n"
  "\n"
  "\tfp = fopen(tmp, \"w\");\n"
  "\tif (fp == NULL)\n"
  "\t\treturn -errno;\n",
  "\tFILE *fp;\n"
  "\tint rc = 0;\n"
  "\tint fd;\n"
  "\tint i;\n"
  "\n"
  "\trc = find_ck_escape(rootesc, sizeof(rootesc), root);\n"
  "\tif (rc != 0)\n"
  "\t\treturn rc;\n"
  "\n"
  "\tfd = find_cookie_tmp(file, tmp, sizeof(tmp));\n"
  "\tif (fd < 0)\n"
  "\t\treturn fd;\n"
  "\tfp = fdopen(fd, \"w\");\n"
  "\tif (fp == NULL) {\n"
  "\t\trc = -errno;\n"
  "\t\tclose(fd);\n"
  "\t\tunlink(tmp);\n"
  "\t\treturn rc;\n"
  "\t}\n")
t("e31be789-probe", PFIND,
  "\tif (snprintf(probe, sizeof(probe), \"%s.new\", cookie) >=\n"
  "\t    (int)sizeof(probe)) {\n"
  "\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, -ENAMETOOLONG,\n"
  "\t\t\t    \"the cookie '%s' is too long to write beside\",\n"
  "\t\t\t    cookie);\n"
  "\t\treturn -ENAMETOOLONG;\n"
  "\t}\n"
  "\n"
  "\tfp = fopen(probe, \"w\");\n"
  "\tif (fp == NULL) {\n"
  "\t\tint rc = -errno;\n"
  "\n"
  "\t\tllapi_error(LLAPI_MSG_ERROR, rc,\n"
  "\t\t\t    \"cannot write the cookie '%s'\", cookie);\n"
  "\t\treturn rc;\n"
  "\t}\n"
  "\tfclose(fp);\n"
  "\tunlink(probe);\n",
  "\tfd = find_cookie_tmp(cookie, probe, sizeof(probe));\n"
  "\tif (fd == -ENAMETOOLONG) {\n"
  "\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, fd,\n"
  "\t\t\t    \"the cookie '%s' is too long to write beside\",\n"
  "\t\t\t    cookie);\n"
  "\t\treturn fd;\n"
  "\t}\n"
  "\tif (fd < 0) {\n"
  "\t\tllapi_error(LLAPI_MSG_ERROR, fd,\n"
  "\t\t\t    \"cannot write the cookie '%s'\", cookie);\n"
  "\t\treturn fd;\n"
  "\t}\n"
  "\tclose(fd);\n"
  "\tunlink(probe);\n")
t("e31be789-probedecl", PFIND,
  "\tchar probe[PATH_MAX];\n"
  "\tstruct stat st;\n"
  "\tFILE *fp;\n"
  "\tint i;\n",
  "\tchar probe[PATH_MAX];\n"
  "\tstruct stat st;\n"
  "\tint fd;\n"
  "\tint i;\n")
t("e31be789-probecmt", PFIND,
  "\t * The probe is find_cookie_write()'s own temporary name, not the\n"
  "\t * cookie: the write creates \"<cookie>.new\" and renames over, so what\n"
  "\t * it needs is permission on the containing directory, which opening\n",
  "\t * The probe is a temporary beside the cookie, as find_cookie_write()\n"
  "\t * makes one, not the cookie: the write renames over, so what it\n"
  "\t * needs is permission on the containing directory, which opening\n")
t("09cfc4b1-2", PFIND,
  "\t * Both refusals here say so.  They used to return the errno alone,\n"
  "\t * where the \"is not a regular file\" case below reports itself, so an\n"
  "\t * empty --since-cookie ended at the caller's \"failed for '<path>':\n"
  "\t * Invalid argument\" with nothing naming the argument at fault.\n",
  "\t * Every refusal here names the argument at fault, or the run would\n"
  "\t * end at the caller's \"failed for '<path>': Invalid argument\".\n")
t("bd138920", PFIND,
  "\tif (rc == 0 && param->fp_since_cookie != NULL) {\n"
  "\t\t/*\n"
  "\t\t * starts[] holds what the file said",
  "\t/*\n"
  "\t * Matches printed into a stdout that failed are as lost as the ones\n"
  "\t * above, and llapi_printf() reports nothing, so ask stdout itself.\n"
  "\t */\n"
  "\tif (rc == 0 && param->fp_since_cookie != NULL &&\n"
  "\t    (fflush(stdout) != 0 || ferror(stdout))) {\n"
  "\t\trc = -EIO;\n"
  "\t\tllapi_error(LLAPI_MSG_ERROR | LLAPI_MSG_NO_ERRNO, rc,\n"
  "\t\t\t    \"the matches could not be written; '%s' is left where it was\",\n"
  "\t\t\t    param->fp_since_cookie);\n"
  "\t}\n"
  "\n"
  "\tif (rc == 0 && param->fp_since_cookie != NULL) {\n"
  "\t\t/*\n"
  "\t\t * starts[] holds what the file said")

# 68419 message: describe the code, not the rounds
t("240ce397-probe", MSG,
  "The pre-pass probes the temporary name the write will use rather than\n"
  "the cookie itself, because the write creates \"<cookie>.new\" and\n"
  "renames over: what it needs is permission on the directory, which\n"
  "opening an existing cookie for append does not test.  A cookie owned\n"
  "by the job user in a root-owned directory passed and then failed\n"
  "EACCES with every match already printed.\n",
  "The pre-pass probes by creating a temporary beside the cookie rather\n"
  "than opening the cookie itself, because the write creates one and\n"
  "renames over: what it needs is permission on the directory, which\n"
  "opening an existing cookie for append does not test.  A cookie owned\n"
  "by the job user in a root-owned directory would pass that and then\n"
  "fail EACCES with every match already printed.\n"
  "\n"
  "The temporary is private to the run, \"<cookie>.<pid>.<n>.new\" created\n"
  "O_EXCL.  One fixed name would let an overlapping run -- a cron job\n"
  "that outlasts its interval -- truncate or unlink the other's copy\n"
  "between its write and its rename, and an empty cookie reads as no\n"
  "anchors at all.  O_EXCL rather than mkstemp() keeps the umask's mode\n"
  "for a first run's cookie.\n"
  "\n"
  "Matches that could not be written hold the anchors too.  They go to\n"
  "stdout through llapi_printf(), which reports nothing, so stdout is\n"
  "flushed and its error flag read before the rewrite; otherwise\n"
  "\"lfs find --since-cookie ck > out\" on a full filesystem would lose\n"
  "the matches, advance past their records and exit 0.\n")
t("240ce397-tail", MSG,
  "The cookie names the search as well as the filesystem, and a\n"
  "mismatch is refused the way a wrong fsname already was.  The anchors\n"
  "say how far each log was read, not how far a subtree was: a record is\n"
  "counted before the FID and the subtree are tested, so a run over one\n"
  "subtree carries every anchor to the end of the log and a second\n"
  "subtree sharing the cookie starts past its own changes and prints\n"
  "nothing.  That is the collision lfs_find() refuses when two paths are\n"
  "given to one command, reached by running the command twice.  A cookie\n"
  "written before this carries no root and is still accepted.\n"
  "\n"
  "A cookie that exists and is not a regular file is refused up front.\n"
  "The probe settles the containing directory, not the name: the write\n"
  "ends in rename(), which answers EISDIR over a directory, while the\n"
  "read succeeds and returns no anchors -- so naming a directory scanned\n"
  "every log to the end, printed every match, and only then said it\n"
  "could not rewrite.  An empty name is refused with it.\n"
  "\n"
  "The comment on the file format said a comment or a blank line costs\n"
  "nothing.  It costs the read nothing; the rewrite emits the header and\n"
  "the anchors and nothing else, so it does not survive the run.  Said\n"
  "so, the sentence otherwise reading as an invitation to annotate the\n"
  "file.\n"
  "\n"
  "The documentation for fp_since_cookie arrives here rather than in the\n"
  "previous patch, which described the field, its -EINVAL and its\n"
  "-ESTALE before any of them existed.\n"
  "\n"
  "The root is the rest of the header line rather than a field.  A\n"
  "pathname can hold a space and %s cuts it at the first one, so a search\n"
  "under \"/mnt/lustre/my data\" was recorded whole and read back as\n"
  "\"/mnt/lustre/my\": the comparison then failed for every run after the\n"
  "first, and the message named a path the caller never gave.  The root\n"
  "is whatever realpath() returned for the caller's path, so a directory\n"
  "with a space in it was enough to reach it.\n"
  "\n"
  "And the root is escaped rather than written raw, because the rest of a\n"
  "line still cannot hold a newline.  Only '/' and NUL are excluded from\n"
  "a name, so \"/mnt/lustre/anb\" was written whole, read back as\n"
  "\"/mnt/lustre/a\", and refused for every run after the first naming a\n"
  "path the caller never gave -- the space case one character further\n"
  "out, with the remainder becoming its own line and being dropped.  Both\n"
  "sides escape and the reader compares the escaped forms, so nothing\n"
  "decodes: the mapping only has to be injective for a comparison, which\n"
  "is also why backslash is escaped.  The refusal names both sides in\n"
  "that spelling, or a newline would break the line meant to name it.\n"
  "\n"
  "find_cookie_check()'s two other refusals say so as well.  An empty\n"
  "--since-cookie and a name too long to append \".new\" to both returned\n"
  "the errno alone, beside a \"is not a regular file\" case that reports\n"
  "itself, so the run ended at the caller's \"failed for '<path>': Invalid\n"
  "argument\" with nothing naming the argument at fault.\n"
  "\n"
  "Two diagnostics that this patch makes reachable are corrected with it.\n"
  "The refusal of --resolve without --changelog said \"--since already\n"
  "reads the object\", which names an option the caller need not have\n"
  "given once --since-cookie exists; it names both anchored spellings\n"
  "now.  And a cookie refused for its filesystem or its root was reported\n"
  "twice, the second line saying \"cannot read\" over a file that read\n"
  "perfectly well -- find_cookie_read() has already named which refusal\n"
  "it was, so the wrapper is left with what fopen() passed up.\n"
  "\n"
  "The MDT number is exactly the four hex digits find_cookie_write()\n"
  "emits.  %4x converts the leading digits and ignores what follows, so\n"
  "\"<fsname>-MDT00001\" and \"<fsname>-MDT0000_UUID\" both anchored MDT0000\n"
  "at an index never written for it -- the short answer with nothing said\n"
  "that the stale check exists to catch, from a file this function's own\n"
  "comment says it ignores anything but \"<mdtname> <index>\" in.  The span\n"
  "refuses the sign as well, so the separate test for it goes.\n"
  "\n"
  "ERRORS gains -ESTALE, which the previous patch dropped on the\n"
  "understanding it would arrive with the cookie and which the kernel-doc\n"
  "Return: block has listed since.  It is the error the whole option is\n"
  "built around, and the man page was the one place a caller of the API\n"
  "could not find it.\n",
  "The cookie names the search as well as the filesystem, and a\n"
  "mismatch is refused the way a wrong fsname is.  The anchors say how\n"
  "far each log was read, not how far a subtree was: a record is counted\n"
  "before the FID and the subtree are tested, so a run over one subtree\n"
  "carries every anchor to the end of the log, and a second subtree\n"
  "sharing the cookie would start past its own changes and print nothing.\n"
  "That is the collision lfs_find() refuses when two paths are given to\n"
  "one command, reached by running the command twice.  A header with no\n"
  "root is accepted.\n"
  "\n"
  "A cookie that exists and is not a regular file is refused up front.\n"
  "The probe settles the containing directory, not the name: the write\n"
  "ends in rename(), which answers EISDIR over a directory, while the\n"
  "read succeeds and returns no anchors -- so a directory named here\n"
  "would scan every log to the end, print every match, and only then say\n"
  "it could not rewrite.  An empty name is refused with it.\n"
  "\n"
  "The root is the rest of the header line rather than a field, because\n"
  "a pathname can hold a space and %s cuts at the first one.  It is\n"
  "whatever realpath() returned for the caller's path.  And it is escaped\n"
  "rather than written raw, because a name can hold a newline, which the\n"
  "rest of a line cannot: only '/' and NUL are excluded from a name.  Both\n"
  "sides escape and the reader compares the escaped forms, so nothing\n"
  "decodes: the mapping only has to be injective for a comparison, which\n"
  "is also why backslash is escaped.  The refusal names both sides in\n"
  "that spelling, or a newline would break the line meant to name it.\n"
  "\n"
  "Every refusal in find_cookie_check() names the argument at fault, so a\n"
  "run does not end at the caller's \"failed for '<path>': Invalid\n"
  "argument\".  The refusal of --resolve without --changelog names both\n"
  "anchored spellings, since --since-cookie reaches it too.  A cookie\n"
  "refused for its filesystem or its root is reported once:\n"
  "find_cookie_read() names the refusal, and the wrapper adds nothing.\n"
  "\n"
  "The MDT number is exactly the four hex digits find_cookie_write()\n"
  "emits.  %4x converts the leading digits and ignores what follows, so\n"
  "without the span \"<fsname>-MDT00001\" and \"<fsname>-MDT0000_UUID\"\n"
  "would both anchor MDT0000 at an index never written for it -- the\n"
  "short answer with nothing said that the stale check exists to catch.\n"
  "The span refuses a sign as well.\n"
  "\n"
  "ERRORS lists -ESTALE, the error the whole option is built around.\n")

# ---------------------------------------------------------------- 68420
t("3d25f00b", MSG,
  "lfs-find.1 gains --since, --since-cookie, --changelog and --resolve:\n"
  "what each answers, that --since is a strict subset of the same search\n"
  "without it, that a bare index belongs to one MDT and is refused where\n"
  "that is ambiguous, that a number which could be an index or an epoch\n"
  "second is never guessed at, and that reading a changelog neither\n"
  "consumes it nor needs a registered user while records exist only while\n"
  "some user is registered.  TIME's spellings are given in full, since\n"
  "set_since() takes eight of them and its error text offers one the page\n"
  "would otherwise not list.\n"
  "\n"
  "The page says what --resolve does not answer for -- an object gone\n"
  "between its event and the lookup is counted undecided and dropped, so\n"
  "--resolve can leave out an object the same search without it reports\n"
  "by FID -- and which name -name is tested against.  The log is\n"
  "coalesced to one record per object before the search sees it, so the\n"
  "name that can match is the one the object's latest event to carry one\n"
  "carried: a file created as f and hardlinked as g is matched by \"-name\n"
  "g\" alone, and the pathname printed is its first name rather than the\n"
  "one that matched.  A plain walk meets each name in turn and matches\n"
  "all of them.  The behaviour is deliberate -- substituting a current\n"
  "name would answer -name against something the record never said -- but\n"
  "a reader had no way to know it.\n",
  "Three changes to lfs-find.1 ride along.  --since-cookie moves up\n"
  "beside --since in SYNOPSIS and OPTIONS: it is the other way to say\n"
  "where a --since search starts, where --changelog is a different\n"
  "source.  TIME's spellings are given in full -- set_since() takes\n"
  "eight of them, and its error text offers one the page would otherwise\n"
  "not list -- and seconds are optional wherever a time appears.  And the\n"
  "-name paragraph says which name a match is tested against under\n"
  "--changelog: the one carried by the object's latest event that\n"
  "carried a name, so a file created as f and then written and closed\n"
  "still matches -name f, its CL_CLOSE naming nothing.\n")
t("6cf9bb05-msg", MSG,
  "and then a stale anchor and both anchors together are refused.  It\n"
  "asks for creations only.  A wide mask records the test's own reads,\n"
  "and then \"nothing changed since\" is never true -- which is what hid an\n"
  "off-by-one in the cookie until a narrow mask made every run repeat the\n"
  "last object of the one before it.\n",
  "and then a stale anchor and both anchors together are refused, as is\n"
  "the cookie under a root other than its own.  A run whose output cannot\n"
  "be written must fail and leave the cookie as it was, so that the run\n"
  "after it still returns the object.  It asks for creations only.  A wide\n"
  "mask records the test's own reads, and then \"nothing changed since\" is\n"
  "never true -- which is what hid an off-by-one in the cookie until a\n"
  "narrow mask made every run repeat the last object of the one before\n"
  "it.\n")
t("6cf9bb05-local", SANITY,
  "\tlocal ck=$TMP/lfs-find-cookie.$$\n"
  "\tlocal out\n",
  "\tlocal ck=$TMP/lfs-find-cookie.$$\n"
  "\tlocal out\n"
  "\tlocal sum\n")
t("6cf9bb05", SANITY,
  "\t[[ -z \"$out\" ]] || error \"the third run returned '$out'\"\n",
  "\t[[ -z \"$out\" ]] || error \"the third run returned '$out'\"\n"
  "\n"
  "\t# bound to the root it was written under, not only the filesystem\n"
  "\tsum=$(cksum < $ck)\n"
  "\tout=$($LFS find $DIR --since-cookie $ck -type f 2>&1) &&\n"
  "\t\terror \"a cookie written under $DIR/$tdir was used under $DIR\"\n"
  "\tgrep -q \"is a cookie for a search under\" <<< \"$out\" ||\n"
  "\t\terror \"refused for another reason: $out\"\n"
  "\t[[ \"$(cksum < $ck)\" == \"$sum\" ]] ||\n"
  "\t\terror \"the cookie refused for its root was rewritten\"\n"
  "\n"
  "\t# matches that could not be written leave the anchors where they were\n"
  "\ttouch $DIR/$tdir/c || error \"touch c failed\"\n"
  "\tsync; sleep 2\n"
  "\t$LFS find $DIR/$tdir --since-cookie $ck -type f > /dev/full \\\n"
  "\t\t2> /dev/null &&\n"
  "\t\terror \"a run whose output was lost reported success\"\n"
  "\t[[ \"$(cksum < $ck)\" == \"$sum\" ]] ||\n"
  "\t\terror \"a run whose output was lost advanced the cookie\"\n"
  "\tout=$($LFS find $DIR/$tdir --since-cookie $ck -type f) ||\n"
  "\t\terror \"the run after a lost one failed\"\n"
  "\tgrep -q \"/c$\" <<< \"$out\" || error \"the run after a lost one missed c\"\n",
  since="c68420")

# ---------------------------------------------------------------- 68727
t("fb139d1b", MSG,
  "the start-point line agree as well belongs to a fix for that, not\n"
  "here.\n",
  "the start-point line agree as well belongs to a fix for that, not\n"
  "here.\n"
  "\n"
  "A trailing slash on something that is not a directory is trimmed too,\n"
  "so \"lfs find f/\" reports f where find(1) fails with ENOTDIR.\n")
t("0957ec61", "lustre/utils/liblustreapi.c",
  " * @path\tStarting path for the traversal\n"
  " * @param\tPonter to find_param structure\n",
  " * @path\tStarting path for the traversal; trailing slashes are ignored\n"
  " * @param\tPointer to find_param structure\n", since="c68727")
t("513bd9ed", "lustre/utils/liblustreapi.c",
  "\t * Here rather than in each caller: this is the one way into the\n"
  "\t * traversal, so",
  "\t * Here rather than in each caller: this is the one way into find's\n"
  "\t * traversal, so")
t("513bd9ed-msg", MSG,
  "It goes in llapi_find_with_cb(), which is the one way into the\n"
  "traversal:",
  "It goes in llapi_find_with_cb(), which is the one way into find's\n"
  "traversal:")
t("836aa67b", PFIND,
  "\t * A walk does print the doubled separator -- llapi_semantic_traverse()\n"
  "\t * appends to the argument as given, and GNU find does the same --\n"
  "\t * so this is the one place --since's spelling differs from the same\n"
  "\t * search without it, deliberately: the set of objects is identical,\n"
  "\t * only the separator is tidied.\n",
  "\t * llapi_find_with_cb() trims a walk's start point the same way, so the\n"
  "\t * two spell names alike.\n", since="c68727")
t("8e5a951e", "lustre/utils/liblustreapi_scan.c",
  "\t * object, so it goes the way llapi_scan_namespace() trims its own\n"
  "\t * path argument.\n",
  "\t * object, so it goes the way llapi_find_with_cb() trims a walk's start\n"
  "\t * point.\n", since="c68727")


# ---------------------------------------------------------------- engine
def allowed(tr, name):
    if tr["only"] is not None and name not in tr["only"]:
        return False
    if tr["since"] is not None and ORDER.index(name) < ORDER.index(tr["since"]):
        return False
    return True


def transform_text(tr, text):
    if "fn" in tr:
        return tr["fn"](text)
    old, new = tr["old"], tr["new"]
    n = text.count(old)
    if n == 0:
        return text, False
    if old in new and new in text:
        return text, False      # insertion already made
    if tr["all"]:
        return text.replace(old, new), True
    if n != 1:
        raise RuntimeError("%s: old text occurs %d times" % (tr["id"], n))
    return text.replace(old, new, 1), True


def apply(tree, name, msg):
    applied = []
    cache = {}
    for tr in T:
        if not allowed(tr, name):
            continue
        if tr["path"] == MSG:
            msg, ok = transform_text(tr, msg)
        else:
            p = os.path.join(tree, tr["path"])
            if tr["path"] not in cache:
                if not os.path.exists(p):
                    continue
                cache[tr["path"]] = open(p).read()
            cache[tr["path"]], ok = transform_text(tr, cache[tr["path"]])
        if ok:
            applied.append(tr["id"])
    for path, text in cache.items():
        p = os.path.join(tree, path)
        if open(p).read() != text:
            open(p, "w").write(text)
    return msg, applied
