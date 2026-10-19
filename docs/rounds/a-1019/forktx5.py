#!/usr/bin/env python3
"""forktx4.py, plus what tx_1019c.py needs: the module sees ANC, the
Change-Ids of the commit and its ancestors from START, and fn() may return
None to delete a file or be asked for one the commit does not change
(mod.ALWAYS).  DRY=1 moves no branch: new tips go to refs/tx1019c/<branch>.
Run from the repository: forktx5.py <start> <module.py>..."""
import subprocess, os, sys, re, importlib.util
BRANCHES = ['fork-1014', 'fork-69501', 'fork-69502', 'fork-69503',
            'rate-1017', 'igif-1017', 'maxrate-1017']  # 68726 abandoned
BRANCHES = os.environ.get('BRANCHES', ' '.join(BRANCHES)).split()
BASE = 'master-1014'
IDX = os.environ.get('TXIDX', '/tmp/claude-1004/-home-nishida-projects-lustre-lfu/12347b89-7a08-40b7-aea7-71d67cc5a5d6/scratchpad/tx5.idx')


def git(*a, inp=None, env=None, raw=False):
    r = subprocess.run(['git'] + list(a), capture_output=True, input=inp,
                       env=env, check=True, text=not raw)
    return r.stdout if raw else r.stdout.strip()


def meta(c):
    env = dict(os.environ)
    for k, f in (('GIT_AUTHOR_NAME', '%an'), ('GIT_AUTHOR_EMAIL', '%ae'),
                 ('GIT_AUTHOR_DATE', '%aI'), ('GIT_COMMITTER_NAME', '%cn'),
                 ('GIT_COMMITTER_EMAIL', '%ce'), ('GIT_COMMITTER_DATE', '%cI')):
        env[k] = git('log', '-1', '--format=' + f, c)
    return env


def cid(c):
    m = re.search(r'^Change-Id: (I[0-9a-f]+)', git('log', '-1', '--format=%B', c), re.M)
    return m.group(1) if m else c


def run(start, mod):
    start = git('rev-parse', start)
    tips = {b: git('rev-parse', b) for b in BRANCHES}
    order = git('rev-list', '--reverse', '--topo-order',
                *[start + '^..' + t for t in tips.values()]).split()
    order = [c for c in order if subprocess.run(
        ['git', 'merge-base', '--is-ancestor', start, c]).returncode == 0]
    newof, anc = {}, {}
    mod.base = lambda p: git('show', BASE + ':' + p, raw=True).decode()
    for c in order:
        par = git('rev-parse', c + '^')
        np = newof.get(par, par)
        subj = git('log', '-1', '--format=%s', c)
        anc[c] = anc.get(par, frozenset()) | {cid(c)}
        mod.ANC = anc[c]
        env = dict(os.environ, GIT_INDEX_FILE=IDX)
        git('read-tree', c + '^{tree}', env=env)
        changed = False
        paths = set(git('diff', '--name-only', BASE, c).split('\n'))
        paths |= set(getattr(mod, 'ALWAYS', ()))
        for path in sorted(p for p in paths if p):
            try:
                s = git('show', c + ':' + path, raw=True).decode()
            except subprocess.CalledProcessError:
                s = None
            except UnicodeDecodeError:
                continue
            t = mod.fn(path, s, subj)
            if t == s:
                continue
            changed = True
            if t is None:
                git('update-index', '--force-remove', path, env=env)
                continue
            blob = git('hash-object', '-w', '--stdin', inp=t.encode(),
                       raw=True).decode().strip()
            mode = '100644'
            if s is not None:
                mode = git('ls-files', '-s', path, env=env).split()[0]
            git('update-index', '--add', '--cacheinfo',
                f'{mode},{blob},{path}', env=env)
        tree = git('write-tree', env=env)
        msg = git('log', '-1', '--format=%B', c).rstrip('\n') + '\n'
        nmsg = mod.msgfn(msg, subj) if hasattr(mod, 'msgfn') else msg
        if np == par and not changed and nmsg == msg:
            newof[c] = c
            continue
        newof[c] = git('commit-tree', tree, '-p', np, inp=nmsg, env=meta(c))
        print('%s -> %s %-48s %s%s' % (c[:10], newof[c][:10], subj[:48],
              'tree' if changed else 'reparent', ' +msg' if nmsg != msg else ''))
    for b, o in tips.items():
        n = newof.get(o, o)
        if os.environ.get('DRY'):
            git('update-ref', 'refs/tx1019c/' + b, n)
        elif n != o:
            git('update-ref', 'refs/heads/' + b, n, o)
        print(b, o[:10], '->', n[:10])


if __name__ == '__main__':
    p = sys.argv[2]
    spec = importlib.util.spec_from_file_location(os.path.basename(p)[:-3], p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    run(sys.argv[1], m)
