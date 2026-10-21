# Round a-1020: AI review on the a1019 PS (polling, 10-20 evening)

| # | change | thread | kind | decision |
|---|--------|--------|------|----------|
| 1 | 68415 PS32 | 77098fc0 sanity.sh:10902 | minor, stale comment | TAKE in the next round batch: the comment (and llapi_scan_changelog_test.c header) still describe the MDD lookup before LU-20647 (52969639ae, already in tree); say "-m ALL is for an MDS without the LU-20647 fix (2.17.0)", as llapi_scan_changelog.3 does. Comment-only, so not worth a fork-wide re-thread on its own. |
| 2 | 68156 PS39 | 6b93ab1e lustreapi.h:811 | style, rename ss_ -> lfss_ | DECLINE (land-ASAP; like the sd_ rename dropped 09-30). Reply at the next push: "Keeping ss_; the stats struct is its own namespace and the rename would touch every scanner." |
