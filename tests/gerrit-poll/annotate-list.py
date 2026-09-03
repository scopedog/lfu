#!/usr/bin/env python3
"""
The Maloo annotate-list: every enforced-test failure on the CURRENT patchset
of every change of ours, as one worklist.

Annotating needs the user's login at testing.whamcloud.com, so this does not
annotate anything.  What it removes is the click-through: without it, finding
the sessions means opening 21 changes and reading past each Verified-1 that
is attached to a "Passed enforced test" message rather than to the failure.

The important half is the split.  Everything matching the LU-20598 signature
-- review-dne-selinux-ssk-part-2, sanity-sec, and nothing else in the session
-- is the tree-wide roll-up and is what the annotation is for.  Anything else
is a failure that is not accounted for, and is printed under OTHER so it
cannot hide inside the noise: a real defect looks exactly like one more red
vote when 21 changes are all red for the same known reason.

Usage: annotate-list.py [--all-patchsets]
"""
import json
import re
import subprocess
import sys

CHANGES = [68094, 68095, 68156, 68157, 68158, 68159, 68160, 68163, 68231,
           68288, 68340, 68413, 68414, 68415, 68416, 68417, 68418, 68419,
           68420, 68616, 68617]

# LU-20598, open: "sanity-sec test_27e: Timeout occurred after 258 minutes,
# last suite running was sanity-sec".  It is a SESSION TIMEOUT, not a subtest
# assertion -- sanity-sec is merely the suite the clock ran out in, and the
# minute count tracks the session budget (241-243 on ours, 258 in the
# ticket).  Tree-wide: 26 of 37 other owners' changes hit it too, which is
# the argument for annotating rather than chasing it.
#
# The catch this cannot solve: Gerrit's message says only "1 tests failed:
# sanity-sec", the same words a real sanity-sec assertion failure would
# produce.  The timeout is visible only in Maloo.  So a row below is a
# CANDIDATE for the annotation and not a confirmed one -- open the session
# and look for the timeout line before annotating it as LU-20598.
KNOWN = {"suite": "review-dne-selinux-ssk-part-2",
         "tests": {"sanity-sec"},
         "ticket": "LU-20598",
         "subtest": "test_27e",
         "signature": "Timeout occurred after N minutes, "
                      "last suite running was sanity-sec"}

SESSION = re.compile(r"https://testing\.whamcloud\.com/test_sessions/"
                     r"[0-9a-f-]+")
ENFORCED = re.compile(r"Failed enforced test (\S+)")
FAILED = re.compile(r"\d+ tests? failed: ([^.]+)\.")


def query():
    q = " OR ".join("change:%d" % c for c in CHANGES)
    r = subprocess.run(["ssh", "-p", "29418", "hnishida@review.whamcloud.com",
                        "gerrit", "query", "--format=JSON", "--comments",
                        "--current-patch-set", q],
                       capture_output=True, text=True, timeout=240)
    out = []
    for line in r.stdout.strip().split("\n"):
        if not line.strip():
            continue
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if o.get("type") == "stats":
            continue
        out.append(o)
    return out


def main():
    every_ps = "--all-patchsets" in sys.argv
    known, other, pending = [], [], []

    for d in sorted(query(), key=lambda x: x["number"]):
        num = d["number"]
        cur = d["currentPatchSet"]["number"]
        seen_any = False
        for c in d.get("comments", []):
            if c["reviewer"].get("username") != "maloo":
                continue
            m = c["message"]
            ps = re.match(r"Patch Set (\d+)", m)
            ps = int(ps.group(1)) if ps else -1
            if not every_ps and ps != cur:
                continue
            seen_any = True
            hit = ENFORCED.search(m)
            if hit is None:
                continue
            suite = hit.group(1)
            url = SESSION.search(m)
            url = url.group(0) if url else "(no session url)"
            tests = FAILED.search(m)
            tests = {t.strip() for t in tests.group(1).split(",")} \
                if tests else set()
            row = (num, ps, suite, sorted(tests), url)
            if suite == KNOWN["suite"] and tests == KNOWN["tests"]:
                known.append(row)
            else:
                other.append(row)
        if not seen_any:
            pending.append((num, cur))

    def show(rows):
        for num, ps, suite, tests, url in rows:
            print("  %-6s PS%-3s %-34s %-22s %s"
                  % (num, ps, suite, ",".join(tests), url))

    print("=== CANDIDATES for %s / %s (%d sessions)"
          % (KNOWN["ticket"], KNOWN["subtest"], len(known)))
    show(known) if known else print("  none")
    if known:
        print("  ^ confirm in Maloo before annotating: LU-20598 is a session")
        print("    TIMEOUT (%s)," % KNOWN["signature"])
        print("    and Gerrit words it the same as a real sanity-sec failure.")

    print()
    print("=== OTHER enforced failures -- NOT accounted for (%d)" % len(other))
    if other:
        show(other)
        print("  ^ read these before annotating anything: a real defect looks")
        print("    like one more red vote when every change is already red.")
    else:
        print("  none")

    if pending:
        print()
        print("=== no Maloo result on the current patchset yet (%d)"
              % len(pending))
        print("  " + ", ".join("%s PS%s" % (n, p) for n, p in pending))

    return 1 if other else 0


if __name__ == "__main__":
    sys.exit(main())
