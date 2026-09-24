# 2026-09-24: Artem's five comments on 68159 PS23 and 68163 PS23

Work tree `~/lfs-artem-0924`, branch `artem-0924`, from the round tip
`218cdea575` (backup: `backup/artem-0924-pre`). Do not use
`~/projects/lustre/lustre-scanfid` for sweeps: it is at `b1-tip` with
staged man-page work that `checkout -f` would lose.

## 68159: --projid is not a layout option -- FIXED, unpushed

`find_check_lmm_info()` includes `fp_check_projid`. On a device scan that
made `--projid N` alone (a) ask the backend for trusted.lov on every object
and (b) count an object with a torn layout as undecided, although its
projid is in the inode. Our own lreview found the same on 09-23
(`b2-0922/lreview-c05-0923d.txt`) and it was held.

Fix at c05 (`f1d26331de` -> `e8f1b401d6`): `find_device_want()` and
`find_rec_layout()` use `find_asks_layout()`. It is already defined above
both, so no forward declaration (Artem's remark on that does not hold).
The walk path (line ~6756 at tip) and the changelog paths are unchanged:
the walk gets projid from the stat, and the changelog paths already test
projid before `find_check_lmm_info()`.

New tip **`2efc8b116b`**: 21/21 commits build (headers, tests too); c05
checkpatch unchanged; below c05 unchanged.

Lab (`lab-projid.sh`, INTERNAL=1: mkimage's files live outside ROOT, and
`tests/find-device/run.sh` is stale for that reason -- it expects 18 and
gets 1): mkimage MDT, plus a copy whose proj1999 has a 32-byte composite
trusted.lov claiming 65535 entries.
- clean: old = new on --projid, ! --projid, --stripe-count 1, no filter.
- torn `--projid 1999`: old 0 + "1 objects could not be decided"; new 1.
- torn `! --projid 1999`: 26 both, old with the undecided warning, new none.
- torn `--stripe-count 1`: undecided in both (correct: it needs the layout).

Held, not in this fix: lreview's second point, that `--size`/`--blocks`
also ask for LAYOUT though a scan does not use the stripe count
(`path == NULL`). Needs proof the backends do not use the layout for
DoM/SOM size first.

Replies, to post only after the push (simple English):
- 3698: "Done. find_device_want() now uses find_asks_layout(), so --projid
  alone does not read trusted.lov."
- 4006: "Done. find_rec_layout() uses find_asks_layout() now. It is defined
  above this function, so no forward declaration is needed. Tested: a file
  with a broken layout is now found by --projid."

Still owed: lreview of c05 before the push; 68163's three comments.
