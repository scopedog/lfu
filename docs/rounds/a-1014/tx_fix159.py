# lreview on 68159': the layout getters return -1 and set errno, so the
# errno to report is -errno, not err (-1) or rc (2); and a typo.
P = 'lustre/utils/liblustreapi_pfind.c'
R = [
 ('\t\t\t\tllapi_error(LLAPI_MSG_ERROR, err,\n\t\t\t\t\t    "error: cannot get last initialized compomnent\\n");\n',
  '\t\t\t\tllapi_error(LLAPI_MSG_ERROR, -errno,\n\t\t\t\t\t    "error: cannot get last initialized component\\n");\n'),
 ('\t\t\t\t\tllapi_error(LLAPI_MSG_ERROR, err,\n\t\t\t\t\t\t    "error: cannot get stripe_count\\n");\n',
  '\t\t\t\t\tllapi_error(LLAPI_MSG_ERROR, -errno,\n\t\t\t\t\t\t    "error: cannot get stripe_count\\n");\n'),
 ('\t\t\t\t\tllapi_error(LLAPI_MSG_ERROR, err,\n\t\t\t\t\t\t    "error: cannot get OST index of last initialized component\\n");\n',
  '\t\t\t\t\tllapi_error(LLAPI_MSG_ERROR, -errno,\n\t\t\t\t\t\t    "error: cannot get OST index of last initialized component\\n");\n'),
 ('\t\t\t\t\tllapi_error(LLAPI_MSG_ERROR, rc,\n\t\t\t\t\t\t    "error: cannot get pool name\\n");\n',
  '\t\t\t\t\tllapi_error(LLAPI_MSG_ERROR, -errno,\n\t\t\t\t\t\t    "error: cannot get pool name\\n");\n'),
 ('\t\t\t\t\tllapi_error(LLAPI_MSG_ERROR, rc,\n\t\t\t\t\t\t    "error: cannot get stripe_size\\n");\n',
  '\t\t\t\t\tllapi_error(LLAPI_MSG_ERROR, -errno,\n\t\t\t\t\t\t    "error: cannot get stripe_size\\n");\n'),
]
def fn(path, s, subj):
    if path != P:
        return s
    for o, n in R:
        if o in s:
            s = s.replace(o, n)
    return s
