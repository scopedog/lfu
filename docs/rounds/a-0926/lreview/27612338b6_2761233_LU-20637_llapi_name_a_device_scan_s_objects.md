# 27612338b6 — LU-20637 llapi: name a device scan's objects

- **Commit:** `27612338b66d` (27612338b6, local review — not tied to a Gerrit change)
- **Review:** 2 finding(s), severity **low**
- **Run:** opus, 5.2M tokens, $3.30, 5m09s

## Overall assessment

Mostly good; two minor points inline, no need to re-spin just for them.

## Findings

### 1. `lustre/utils/liblustreapi_pfind.c` (line 3531)

(minor) For a hardlinked object, find_device_prefilter() matches --name against every linkea entry, but only in its local copy `named`. find_device_cb() then hands the original rec to find_decide(), and here the path is composed from `lfsr_name`, which is always linkea entry 0.

So with f0 and hardlink being one inode:

    lfs find --device $MDT --paths ! --name f0

prints `/dir/f0`, a name the predicate excluded. `--name hardlink` prints `/dir/f0` too.

Under DNE, when entry 0's parent is on another MDT, the object is counted as nameless even though a later entry's parent is in this MDT's map.

Would it be better to compose from the entry that matched, or from the first entry the map can place?

### 2. `Documentation/man1/lfs-find.1` (line 954)

(minor) This says an object is printed once, but on an OST the unit is the object, not the file. A PFL file with several components on the scanned OST, or an overstriped file, has several objects there with the same owner, so --fid2path prints the same pathname several times. The code comment in find_decide() and llapi_scan_rec_path() both say "once per stripe", but lfs-find(1) does not.

If the patch is refreshed, could this say that an OST scan may repeat a pathname, so a script feeding the list to a copy tool knows to `sort -u` it?
