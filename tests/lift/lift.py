#!/usr/bin/env python3
"""Extract functions verbatim from the shipped sources into the harness.

Retyping a function into a harness tests the copy, not the code.  These are
cut out of the real files by name and brace-matched, so the harness compiles
whatever the tree currently says -- and the fixed and unfixed arms differ
only by the tree they were cut from.
"""
import re, sys

def lift(path, name):
    s = open(path).read()
    m = re.search(r'^[a-zA-Z_].*\b%s\(' % re.escape(name), s, re.M)
    if not m:
        sys.exit("no definition of %s in %s" % (name, path))
    # back up over the comment block above it
    start = m.start()
    head = s[:start].rstrip()
    if head.endswith('*/'):
        start = head.rfind('/*')
    depth = 0; i = m.start(); seen = False
    while i < len(s):
        if s[i] == '{': depth += 1; seen = True
        elif s[i] == '}':
            depth -= 1
            if seen and depth == 0:
                return s[start:i+1] + "\n"
        i += 1
    sys.exit("unbalanced braces for %s" % name)

if __name__ == "__main__":
    T = sys.argv[1]
    out = []
    out.append(lift(T + "/lustre/utils/liblustreapi_scan_device.c", "scan_linkea_entry"))
    out.append(lift(T + "/lustre/utils/liblustreapi_pfind.c", "find_prefilter"))
    out.append(lift(T + "/lustre/utils/liblustreapi_pfind.c", "find_device_prefilter"))
    open(sys.argv[2], "w").write("".join(out))
    print("lifted %d bytes" % sum(len(x) for x in out))
