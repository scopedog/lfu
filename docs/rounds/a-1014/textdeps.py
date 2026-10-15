import subprocess, os, sys, json
R=os.path.expanduser('~/lfs-fix-1007'); D=sys.argv[1]
def git(*a, env=None, check=True):
    return subprocess.run(['git','-C',R]+list(a),capture_output=True,text=True,env=env,check=check)
commits=git('rev-list','--reverse','master-1014..af3375dbba').stdout.split()
patches={}
for c in commits:
    p=os.path.join(D,c+'.patch'); open(p,'w').write(git('format-patch','-1','--stdout','--binary',c).stdout); patches[c]=p
idx=os.path.join(D,'idx')
def applies(seq):
    env=dict(os.environ, GIT_INDEX_FILE=idx)
    git('read-tree','master-1014',env=env)
    for c in seq:
        r=subprocess.run(['git','-C',R,'apply','--cached',patches[c]],env=env,capture_output=True)
        if r.returncode: return False
    return True
deps={}
for i,c in enumerate(commits):
    S=commits[:i]
    for j in reversed(commits[:i]):
        T=[x for x in S if x!=j]
        if applies(T+[c]): S=T
    deps[c]=S
    print('C%d'%(i+1), '<-', ' '.join('C%d'%(commits.index(x)+1) for x in S), flush=True)
json.dump({c:deps[c] for c in commits}, open(os.path.join(D,'textdeps.json'),'w'))
