#!/usr/bin/env python3
"""Lift find_cookie_check() and find_cookie_was_empty() verbatim from a
liblustreapi_pfind.c.  Usage: lift.py SRC OUT"""
import re, sys
s = open(sys.argv[1]).read()
out = []
for fn in ('find_cookie_was_empty', 'find_cookie_check'):
    m = re.search(r'^static int ' + fn + r'\(.*?^}\n', s, re.M | re.S)
    out.append(m.group(0))
open(sys.argv[2], 'w').write('\n'.join(out))
