# lreview on 68418': a predicate the record can never answer is refused, not
# counted undecided; and naming the log for a bare index changes the answer.
R = {
'Documentation/man3/llapi_find_since.3': [(
""".I fp_resolve
is set, there being no pathname to bound it with; and a predicate the record
cannot answer is counted undecided and reported once at the end rather than
guessed at. See
""",
""".I fp_resolve
is set, there being no pathname to bound it with. A predicate the record can
never answer, such as
.B -size
or
.BR -perm ,
is refused with
.B -ENOTSUP
before the log is read unless
.I fp_resolve
is set;
.B -type
or
.B -name
on a record that does not carry the type or a name is counted undecided and
reported once at the end rather than guessed at. See
""")],
'lustre/utils/liblustreapi_pfind.c': [(
""" * refused rather than widened.  A predicate the record cannot answer
 * is counted undecided and reported at the end rather than guessed at.
""",
""" * refused rather than widened.  A predicate a record can never answer is
 * refused with -ENOTSUP unless --resolve is given; -type or -name on a
 * record that lacks them is counted undecided and reported at the end.
""")],
'Documentation/man1/lfs-find.1': [(
""".I cr_index
belongs to one MDT and names a different instant on each of them. Nothing else
""",
""".I cr_index
belongs to one MDT and names a different instant on each of them. Naming the
log that way makes it a
.B --changelog
search, answered as recorded rather than through the mount; see below.
Nothing else
""")],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
