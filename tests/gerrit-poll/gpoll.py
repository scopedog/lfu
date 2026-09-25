import json, re, subprocess, sys, os, datetime
STATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'seen.json')
# Every change of ours in review.  A change pushed and not added here is
# INVISIBLE to this watch -- which is how 68340 stayed out of the 2026-08-27
# morning check.  68616 and 68617 are the two preparatory changes round 19
# added at the bottom of the stack.
CHANGES = [68094,68095,68156,68157,68158,68159,68160,68163,68231,68288,68340,
           68413,69206,68414,68415,68416,68417,68418,68419,68420,68616,68617,
           # round 22 created these two: the batch API and the slash trim
           68726,68727]
Q = " OR ".join("change:%d" % c for c in CHANGES)

def fetch():
    r = subprocess.run(["ssh","-p","29418","hnishida@review.whamcloud.com",
                        "gerrit","query","--format=JSON","--comments",
                        "--current-patch-set",Q],
                       capture_output=True, text=True, timeout=180)
    out=[]
    for line in r.stdout.strip().split("\n"):
        if not line.strip(): continue
        try: o=json.loads(line)
        except Exception: continue
        if o.get("type")=="stats": continue
        out.append(o)
    return out

def key(n,c): return "%d|%d|%s|%s" % (n,c["timestamp"],c["reviewer"].get("username",""),c["message"][:50])

seen=set()
if os.path.exists(STATE):
    seen=set(json.load(open(STATE)))

changes=fetch()
if not changes:
    sys.exit(0)                      # transient; say nothing, try again next tick

seeding = not seen
events=[]
lu20598=[]
for d in changes:
    n=d["number"]; cur=d["currentPatchSet"]["number"]
    for c in d.get("comments",[]):
        k=key(n,c)
        if k in seen: continue
        seen.add(k)
        if seeding: continue
        m=c["message"]; who=c["reviewer"].get("username","?")
        psm=re.match(r"Patch Set (\d+)",m)
        ps=int(psm.group(1)) if psm else -1
        # filter 1: a message against a superseded patchset needs no action
        if ps!=-1 and ps!=cur: continue
        # filter 2: LU-20598.  Rolled up rather than dropped -- it is
        # deterministic and needs no triage, but it is also what gates the
        # series now, and silence hid three of these on current patchsets.
        if "review-dne-selinux-ssk-part-2" in m and "sanity-sec" in m:
            lu20598.append(n); continue
        # noise: the bare "sessions will be run" announcement
        if who=="maloo" and "sessions will be run" in m: continue
        # our own push: 18 of these arrive at once and none is information
        if who=="hnishida" and re.match(r"Uploaded patch set \d+", m): continue
        # our own review replies: a round answers dozens of threads at once and
        # every one of them comes back as "Patch Set N: (K comments)".  What we
        # just wrote is never news; a human reply still is, and this is anchored
        # to our username so it cannot swallow one.
        if who=="hnishida" and re.match(r"Patch Set \d+:\s*$", m.splitlines()[0]) \
           and re.search(r"^\(\d+ comments?\)$", m, re.M): continue
        t=datetime.datetime.fromtimestamp(c["timestamp"]).strftime("%m-%d %H:%M")  # local, as `date`
        # a vote, not the "Outdated Votes:" listing a push leaves behind
        vote=""
        if re.search(r"^Patch Set \d+: Verified-1", m, re.M): vote=" **Verified-1**"
        elif re.search(r"^Patch Set \d+: Verified\+1", m, re.M): vote=" Verified+1"
        mm=re.search(r"Failed enforced test (\S+).*?tests failed: (\S+?)\.",m,re.S)
        if mm:
            crash="  %%CRASHED%%" if "CRASHED" in m else ""
            events.append("%s %s PS%d %s: FAILED %s / %s%s%s" % (t,n,cur,who,mm.group(1),mm.group(2),crash,vote))
        elif who=="aireview":
            cm=re.search(r"\((\d+) comments?\)",m)
            events.append("%s %s PS%d AI REVIEW -- %s comments" % (t,n,cur,cm.group(1) if cm else "?"))
        elif who not in ("maloo","jenkins","lgerritjanitor","hpdd-checkpatch",
                         "smatchreview","autotest","lustre-riscv-builder","hnishida"):
            events.append("%s %s PS%d HUMAN %s: %s" % (t,n,cur,who,m.splitlines()[0][:110]))
        else:
            first=" | ".join(x for x in m.split("\n") if x.strip())[:130]
            events.append("%s %s PS%d %s: %s%s" % (t,n,cur,who,first,vote))

json.dump(sorted(seen), open(STATE,"w"))
for e in sorted(events): print(e, flush=True)
if lu20598 and not seeding:
    u=sorted(set(lu20598))
    print("%s LU-20598 sanity-sec: %d new on %s" %
          (datetime.datetime.now().strftime("%m-%d %H:%M"), len(lu20598),
           ",".join(str(x) for x in u)), flush=True)
