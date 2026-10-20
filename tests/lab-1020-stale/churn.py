#!/usr/bin/python3
# Create c<i> and unlink c<i-K> until <stopfile> appears; one process, so a
# file's FID oid and its <i> rise together.  Usage: churn.py dir K stopfile
import os, sys
d, k, stop = sys.argv[1], int(sys.argv[2]), sys.argv[3]
i = 0
while not os.path.exists(stop):
    for _ in range(100):
        os.close(os.open("%s/c%d" % (d, i), os.O_CREAT | os.O_WRONLY, 0o644))
        if i >= k:
            os.unlink("%s/c%d" % (d, i - k))
        i += 1
print("churn created", i)
