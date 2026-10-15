# Em-dashes in older wordings that a later commit rewrites, so the tip-based
# pass (tx_emdash.py) could not reach them.  Same style as that pass.
R = {
'Documentation/man3/llapi_scan_device.3': [
 ('are deliberately distinct \\(em a caller that skips its work where a build\n',
  'are deliberately distinct: a caller that skips its work where a build\n')],
'Documentation/man3/llapi_scan_namespace.3': [
 ('once, then as filtered, skipped, or delivered and namespace-visible \\(em\n'
  'everything a walk reaches arrived through a directory entry, so the other\n',
  'once, then as filtered, skipped, or delivered and namespace-visible.\n'
  'Everything a walk reaches arrived through a directory entry, so the other\n')],
'Documentation/man3/llapi_find_device.3': [
 ('is outside the range this library accepts \\(em shorter than its minimum,\n',
  'is outside the range this library accepts: shorter than its minimum,\n')],
'Documentation/man3/llapi_find_since.3': [
 ('records nothing at all \\(em\n.B mdd_changelog_off()\n',
  'records nothing at all:\n.B mdd_changelog_off()\n'),
 ('as the arguments are well formed \\(em before\n.I path\n',
  'as the arguments are well formed, before\n.I path\n'),
 ('names no Lustre mount \\(em\n.BR llapi_search_fsname (3)\n',
  'names no Lustre mount.\n.BR llapi_search_fsname (3)\n'),
 ('no anchor. Refused for the anchored form \\(em there is nothing to search\n'
  'since \\(em but it is the ordinary setting when\n',
  'no anchor. Refused for the anchored form (there is nothing to search\n'
  'since), but it is the ordinary setting when\n')],
'Documentation/man1/lfs-find.1': [
 ('the search sees it. An object the log named more than once \\(em a file\n',
  'the search sees it. An object the log named more than once (a file\n'),
 ('.I g\n\\(em is therefore matched by\n',
  '.IR g )\nis therefore matched by\n')],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if s.count(o) == 1:
            s = s.replace(o, n)
    return s
