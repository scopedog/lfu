# Lab 2026-10-20: OSD scanner inode-reuse guard + LU-20730 items 1 and 3

Branch `lu-20720-stale` in ~/lfs-osd-1007 (backups p1020-pre-stale,
p1020-stale-{1,2,3}).  VMs rhel9.7-server-mgs-mds-clone (MDS+OSS, arms run
from their build trees, nothing installed) and rhel9.7-client-clone.

## Build sweep (01-build.sh, 01b)
Modules at e96d551119, 40d019feda, c06be0c566 (=c3), 0de0be6c85 (c3b), full
trees at the old tip (c9c2c6319b) and new tips (4ca1475ba1, 4355897466).
All rc=0.  Every tree, old included, needs KCFLAGS=-Wno-error=unused-label:
llite/namei.c `again:` is unused on this kernel config (base tree, not ours).

## (a) inode reuse between next() and the xattr reads
- Random churn + 2 ms delay per object (02-run.sh): no reuse in the window
  on either arm, 0 mixed, 0 stale.  Why (04-reuse-probe.sh): the MDT keeps
  an unlinked inode until its object leaves the cache, so freed inode numbers
  are not reused for seconds; with drop_caches every 0.2 s reuse happens
  (54 of 454 inode numbers renamed between rounds) but almost never inside
  one object's window.
- Targeted (05-targeted.sh, lab_delay_ino): 4 s sleep on x's inode, x
  unlinked, caches purged, files created until x's inode is taken (y1.1):
  - old: emits x's FID 0x200001b71:0x2 with the NAME y1.1 (whose FID is
    :0x3) -- a mixed record.  ls_stale n/a.
  - new: no record for the inode; seen 6108, emitted 6107, ls_stale 1.
- Quiescent fixture: ring 5104 = 5104 records both arms; llapi_scan_mount
  5017 = 5017, diff 0.  (Ring diffs are MDT-internal llogs rewritten by the
  remount, and a harness column added between runs.)

## Side finding (not changed)
Unlinked-but-cached inodes come back in the raw stream WITH their names:
400 of 601 churn-dir records were files already unlinked.  ext4 keeps the
orphan-list link in i_dtime, so the raw parse's "links 0, mode and dtime
set = orphan" rule lets them through.  Whether the userspace classifier
holds them back was not checked.

## LU-20730 item 1: CAP_DAC_READ_SEARCH (scanioctl.c, LL_IOC_LFU_SCAN)
nobody EPERM; nobody+CAP_DAC_READ_SEARCH ok (19 pages); nobody+CAP_SYS_ADMIN
only EPERM; root ok.  Note: llapi_scan_mount() for a non-root caller fails
earlier, reading the MDT list from /sys/kernel/debug (root-only), and
reports it as "cannot open <mount>: ENOENT" -- misleading, ours, not fixed.

## LU-20730 item 3: tenant filter (03-tenant-*.sh)
Fixture: t* (100) uid/gid 100500, g* (50) uid 600 gid 100700, u* (100)
600:600; t0 projid 100900.  Offsets 100000/100000 for uid, gid, projid.
- nodemap off: 257 records.  default nodemap (admin 0, trusted 0):
  llapi_scan_mount -EPERM.  default admin+trusted: 257.
- tenant nodemap (client NID, admin+trusted, offset): 150 = t 100 + g 50,
  no u, no dirs/ROOT.  IDs mapped: t0 500 500 900, t1 500 500 65534
  (projid 0 out of range), g0 65534 700 65534 -- the same IDs `stat`
  shows through that client.

## Round 2: after the lreview fixes (tip 33baf7f1c6 code = f057ebada1)
Build sweep: full tip + modules at all seven kernel commits, rc=0.
- **Unmount, first attempt CRASHED the VM** (class_incref + OBDF_STOPPING on
  the OSD obd): osd_shutdown() runs from mdt_stack_fini() inside the MDT's
  class_cleanup(), before the OSD obd stops or is released, so the LASSERT
  in osd_scrub_cleanup() fired (vmcore /var/crash/127.0.0.1-2026-10-20-16:23:48).
- Fix: osd_scrub_cleanup() sets od_otable_stopping and waits for private
  iterators; private next() -> -ESHUTDOWN; DORA_STATS dos_stopping; lfu
  polls it every 1 s while stalled.  06-umount-link.sh, ring 64 KiB,
  reader not reading: MDT umount rc=0 in 1.09 s, reader ESHUTDOWN, 0 LBUG.
- Big link (151 names, ~4 KB trusted.link): old arm llapi_scan_mount
  rc=-7 (E2BIG) at 4547 records; new: rc=0, 6027 records, the file carried
  as LFU_REC_LINK_BIG (no name).
- Targeted reuse (05-targeted.sh ten3): stale=1, no record for the inode.
- Tenant gate (03-tenant-*.sh, T=/tmp/stale-ten3): off 257; default
  nodemap -EPERM; admin+trusted 257; tenant 150 mapped; tenant admin=0
  (squashed root) -EPERM; rbac without byfid_ops -EPERM; fileset /ten
  -EPERM; restoring each gives 150 back.  ioctl: nobody EPERM,
  +CAP_DAC_READ_SEARCH ok, +CAP_SYS_ADMIN only EPERM.
- Not lab-tested: the crafted-request rejection in dt_index_read() (needs
  a modified client), the read() mutex (needs two racing readers), zeroed
  reply pages (no reader of the stale bytes).

## Round 3: second lreview fixes (tip d39f75a12c)
Fixed: lfu.ko EOF race (done read with acquire, head re-read), singleton
mode removed (private param gone: DOIF_RESET drove OI scrub and LASSERTed at
unmount), otable object put before fini(), record pad zeroed (ring and RPC
builders: a kept record's pad could carry a dropped record's name), ioctl
'f' 234 (221 is lustre_ioctl.h's), LINK_BIG docs, fileset read under
nm_fileset_alt_lock, tenants allowed WITH a fileset (the ID ranges stand
in for it), a non-offset nodemap refused if it or its parent has one.
Builds: modules at 68814/68816/68817, full tip, rc=0.
- Lab trap: lab-delay.sh anchored on the removed private_it line, the lfu
  module never built, llmount.sh then loaded the VM's INSTALLED Lustre and
  the srcversion check compared two empty strings.  Scripts now check the
  .ko exists and check obdclass too, and the lab patch fails loudly.
- 06: big link carried, 6631 records rc 0; unmount 1.12 s, reader
  ESHUTDOWN, 0 LBUG.  05 (fresh dir): stale=1, record dropped.
- Tenant (T=/tmp/stale-ten4, client mdc srcversion checked): off 257;
  ioctl nobody EPERM / +DAC_READ_SEARCH ok / +SYS_ADMIN EPERM; default
  -EPERM; admin 257; tenant 150; squashed -EPERM; no byfid -EPERM;
  tenant + fileset 150; fileset without offset -EPERM; neither 257.
