# Replies to adilger on 68156 PS35 (drafts, 10-14)

Posted with the fork push, each on its thread (full comment ids below).

1. `3c1dd70c_5971dacb` /PATCHSET_LEVEL, fork the series
   > Done. The series is now a tree: 68415 and 68416 sit on 68156; 69501
   > and 69502 on 68417; 69503 on 68163; 68726 on 68415. 68420's tests
   > moved into 68417, 68418 and 68419, and 68420 is abandoned.

2. `849bc2b4_5374118c` llapi_scan_device.3:30, rate control
   > Agreed. It is not in this series yet. It will be a change of its own
   > near the bottom of the tree, a limit in llapi_scan_param that both
   > scanners honour.

3. `183dd9f7_cd561bdb` llapi_scan_device.3:154, em-dashes
   > Done, in all the pages this series adds.

4. `5b25e980_83acd896` llapi_scan_device.3:234, 1.8 filesystems
   > Done. The 1.8 case is gone; the page names a link or an LMA lost to
   > xattr corruption instead.

5. `e355d9d5_0530b909` llapi_scan_namespace.3:60, rate limit for the walk
   > Yes, the namespace walk will honour the same limit.

6. `bd247096_ad0471d4` lustre_fid.h:369, 2.4 is not new
   > Done. An IGIF root is a real gap for --paths, though:
   > scan_dirmap_path() stops only at LU_ROOT_FID, so on such a filesystem
   > every path comes back -ENOENT. A follow-up will take the root FID from
   > the target.

7. `afd12c69_7cd3d5f5` conf-sanity.sh:13356, echo instead of skip
   > Done. test_300 is split into 300a (the MDT), 300b (the OST) and 300c
   > (the --local sweep); each skips with the version or the reason.

8. `95aa0721_468d8886` conf-sanity.sh:13370, OST object FID or MDT FID
   > lfsr_fid is the scanned object's own FID, the OST object's here. The
   > owning file's MDT FID comes with LLAPI_SCAN_OWNER as lfsr_owner_fid,
   > and lfs find --fid2path and --paths name an OST object by it. I would
   > keep one meaning for lfsr_fid and let a tool ask for the owner.
   > Migrated and replicated objects: noted; there is no flag for them yet,
   > and the record has room for one.

9. `034d05b4_2f39084c` llapi_scan_device_test.c:45, tier-0 mask
   > It is an upper bound: the test fails only if a record carries a bit
   > outside it, not if BTIME or PROJID is missing.
