import subprocess, os, re, sys, collections
R=os.path.expanduser('~/lfs-fix-1007'); M=sys.argv[1]
TOK=re.compile(r'\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b')
master=set()
for root,_,fs in os.walk(M):
    for f in fs:
        try: master.update(TOK.findall(open(os.path.join(root,f),errors='ignore').read()))
        except Exception: pass
def git(*a): return subprocess.run(['git','-C',R]+list(a),capture_output=True,text=True).stdout
commits=git('rev-list','--reverse','master-1014..af3375dbba').split()
name={c:'C%d'%(i+1) for i,c in enumerate(commits)}
intro={}; added_lines={}
uses=collections.defaultdict(dict); edits=collections.defaultdict(dict)
seen=set()
for i,c in enumerate(commits):
    d=git('show','--format=','-U0',c)
    plus=[];minus=[];f=None
    for l in d.split('\n'):
        if l.startswith('+++ '): f=l[6:]; continue
        if l.startswith('--- '): continue
        if l.startswith('+'): plus.append((f,l[1:]))
        elif l.startswith('-'): minus.append((f,l[1:]))
    toks=set(t for _,l in plus for t in TOK.findall(l))
    mt=set(t for _,l in minus for t in TOK.findall(l))
    new=toks-master-seen
    intro[c]=new; seen|=new
    for j in commits[:i]:
        u=(toks|mt) & intro[j]
        if u: uses[c][j]=u
    for f,l in minus:
        s=l.strip()
        if len(s)<8: continue
        for j in reversed(commits[:i]):
            if (f,s) in added_lines.get(j,set()):
                edits[c][j]=edits[c].get(j,0)+1; break
    added_lines[c]=set((f,l.strip()) for f,l in plus)
for c in commits:
    deps=set(uses[c])|set(edits[c])
    print(name[c], '<-', ' '.join(sorted((name[j] for j in deps), key=lambda x:int(x[1:]))))
    for j in sorted(deps, key=commits.index):
        u=sorted(uses[c].get(j,()))
        print('    %s: uses %d %s%s' % (name[j], len(u), ', '.join(u[:8]), ('; edits %d lines'%edits[c][j]) if edits[c].get(j) else ''))
