#!/usr/bin/env python3
"""Rewrite the forked series in place: every commit from START up, on every
fork branch, gets fn() applied to each file its tree changes against master,
and msgfn() to its message.  Parents are remapped, author and dates kept.
Run from ~/lfs-fork-1014.  A module defining fn/msgfn is passed by path."""
import subprocess, os, sys, importlib.util
BRANCHES = ['fork-1014', 'fork-69501', 'fork-69502', 'fork-69503', 'fork-68726']
BASE = 'master-1014'
IDX = '/tmp/claude-1004/-home-nishida-projects-lustre-lfu/b3736538-c7fe-4fa3-bd7f-c18e5e3ed3e8/scratchpad/tx.idx'
def git(*a, inp=None, env=None, raw=False):
    r = subprocess.run(['git'] + list(a), capture_output=True, input=inp, env=env, check=True,
                       text=not raw)
    return r.stdout if raw else r.stdout.strip()
def meta(c):
    env = dict(os.environ)
    for k, f in (('GIT_AUTHOR_NAME','%an'),('GIT_AUTHOR_EMAIL','%ae'),('GIT_AUTHOR_DATE','%aI'),
                 ('GIT_COMMITTER_NAME','%cn'),('GIT_COMMITTER_EMAIL','%ce'),('GIT_COMMITTER_DATE','%cI')):
        env[k] = git('log', '-1', '--format=' + f, c)
    return env
def run(start, mod, only=None):
    """only: optional set of commit subjects (prefix) to touch; others are
    reparented but keep their tree only if fn changes nothing in them."""
    start = git('rev-parse', start)
    order = git('rev-list', '--reverse', '--topo-order',
                *[start + '^..' + b for b in BRANCHES]).split()
    def descends(c):
        return subprocess.run(['git', 'merge-base', '--is-ancestor', start, c]).returncode == 0
    order = [c for c in order if descends(c)]
    newof = {}
    for c in order:
        par = git('rev-parse', c + '^')
        np = newof.get(par, par)
        subj = git('log', '-1', '--format=%s', c)
        env = dict(os.environ, GIT_INDEX_FILE=IDX)
        git('read-tree', c + '^{tree}', env=env)
        changed = False
        for path in git('diff', '--name-only', BASE, c).split('\n'):
            if not path: continue
            try:
                data = git('show', c + ':' + path, raw=True)
            except subprocess.CalledProcessError:
                continue
            try:
                s = data.decode()
            except UnicodeDecodeError:
                continue
            t = mod.fn(path, s, subj)
            if t != s:
                blob = git('hash-object', '-w', '--stdin', inp=t.encode(), raw=True).decode().strip()
                mode = git('ls-files', '-s', path, env=env).split()[0]
                git('update-index', '--cacheinfo', f'{mode},{blob},{path}', env=env)
                changed = True
        if hasattr(mod, 'tree_fn'):
            files = {}
            for path in set(mod.R) | {'lustre/utils/liblustreapi_pfind.c'}:
                try:
                    files[path] = git('show', c + ':' + path, raw=True).decode()
                except subprocess.CalledProcessError:
                    pass
            for path, t in mod.tree_fn(files).items():
                if t == files.get(path):
                    continue
                blob = git('hash-object', '-w', '--stdin', inp=t.encode(), raw=True).decode().strip()
                mode = git('ls-files', '-s', path, env=env).split()[0]
                git('update-index', '--cacheinfo', f'{mode},{blob},{path}', env=env)
                changed = True
        tree = git('write-tree', env=env)
        msg = git('log', '-1', '--format=%B', c) + '\n'
        nmsg = mod.msgfn(msg, subj) if hasattr(mod, 'msgfn') else msg
        if np == par and not changed and nmsg == msg:
            newof[c] = c
            continue
        newof[c] = git('commit-tree', tree, '-p', np, inp=nmsg, env=meta(c))
        print('%-48s %s%s' % (subj[:48], 'tree' if changed else 'reparent', ' +msg' if nmsg != msg else ''))
    for b in BRANCHES:
        o = git('rev-parse', b)
        if newof.get(o, o) != o:
            git('update-ref', 'refs/heads/' + b, newof[o], o)
        print(b, o[:10], '->', newof.get(o, o)[:10])
if __name__ == '__main__':
    spec = importlib.util.spec_from_file_location('m', sys.argv[2])
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    run(sys.argv[1], mod)
