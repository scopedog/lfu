# Round 21 — the Gerrit AI backlog answered, 2026-09-04

After the push (18 changes, 18 new patchsets), **113 `aireview` threads
were unresolved and none of them had a reply from me.** Every earlier
round fixed the findings and never said so on Gerrit; 460 of my comments
sit on threads that *were* answered, so this was a backlog rather than a
habit.

**103 replied and resolved. 10 left open with no reply — see below.**

## How

`gerrit query --comments` returns change *messages* only. Inline threads
need the REST API:

    curl -s https://review.whamcloud.com/changes/<n>/comments   # anonymous read works

A thread's state is its **last** comment's `unresolved` flag, not the
AI's own. Replying into a thread needs `in_reply_to`, which the ssh
`gerrit review` command accepts because `--json` takes the same
ReviewInput as REST:

    ssh -p 29418 hnishida@review.whamcloud.com gerrit review <n>,<ps> --json \
      <<< '{"tag":"review-reply","notify":"OWNER","comments":{"<path>":[
            {"line":N,"in_reply_to":"<full comment id>","unresolved":false,
             "message":"..."}]}}'

The **full** comment id is required — the eight-character prefix Gerrit
shows in the UI is not an id. `post.py` in the scratchpad maps prefixes
to full ids out of the fetched JSON and batches every reply for a change
into one call, so 18 changes cost 18 notifications rather than 113.

## Five left open on purpose, each with a reply saying why

| change | thread | why |
|---|---|---|
| 68159 | `e6fb45c4` | the DoM `--size 0` defect — measured, real, deliberately unfixed (needs a LOV parser the scan backend does not have) |
| 68288 | `8d405103` | false positive, disproved by building the filesystem; its secondary point (skip the directory pass on an OST via `tt_flags`) stands and is recorded |
| 68417 | `122b863e` | `llapi_get_target_uuids()` instead of 64 `llapi_search_tgt()` probes — right, but startup-only; left so it is not lost |
| 68417 | `cda04667` | an object touched twice inside the window prints twice; both fixes cost memory proportional to the answer, so it is a design call |
| 68420 | `39df2275` | declined — alphabetising would scatter the four changelog options, and `--resolve` is refused without `--changelog` |

## Ten NOT replied to: the reviews that landed after round 20's triage

The AI reviewed the pre-push patchsets through the day. Everything up to
**12:38** was triaged and fixed before the push, so those threads got
"Done" replies. Two reviews arrived after that work was finished and have
**not been looked at**:

- **68419 `2926fe9e` `d1c134a5` `797f62e9` `3eb08208`** — 13:14
- **68420 `b18c8800` `2a56e006` `8675182e` `bb69b7c6` `48df9797` `ff135a8f`** — 14:41

`2926fe9e` is the one to read first: it is the **newline** sibling of the
space bug lreview found in the cookie header, one character further out
than `%n` fixed. It fails closed rather than answering short.

These are the round-22 queue. Replying "Done" to them would have been a
lie, which is the whole reason the split is recorded here.

## Also posted

A disclosure on 68163: the two ZFS fixes on it — the SA handle leak on
the xattr path and the errno split — **have never executed**. This lab
builds `ENABLE_ZFS='no'`, so they are compile-checked against libzfs 2.2
headers and reasoned against ZFS's own `sa.c`, and nothing more.
