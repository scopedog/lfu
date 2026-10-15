# lreview on 68415': _CLEAR clears in batches, so it is at-least-once.
M = 'Documentation/man3/llapi_scan_changelog.3'
O = 'Purge consumed records as they are accepted, never ahead of the consumer. A\n'
N = ('Purge consumed records, never ahead of the consumer: every thousand or so\n'
     'while the stream runs, and the rest when it ends. A consumer killed\n'
     'mid-stream, or one that follows a log that has gone quiet, leaves up to that\n'
     'many consumed records uncleared, and they are delivered again on the next\n'
     'run: a consumer using this as its checkpoint sees each record at least once,\n'
     'not exactly once. A\n')
def fn(path, s, subj):
    return s.replace(O, N) if path == M else s
