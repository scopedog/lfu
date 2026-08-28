# `gpoll.py` — the routine's 30-minute Gerrit watch

Emits only Gerrit messages not seen before, so a quiet tick is silent. Keeps a
`seen.json` beside itself; **the first run records everything as seen and
prints nothing**, which is how you seed it.

```sh
python3 gpoll.py                 # seed, then poll
while true; do sleep 1800; python3 gpoll.py; done    # under Monitor, persistent
```

Monitor's own timeout caps at one hour, shorter than a sweep, so it needs
`persistent: true`.

## Filters (the user's, set 2026-08-26)

- anything against a **superseded patchset** — needs no action;
- `review-dne-selinux-ssk-part-2` + `sanity-sec` — LU-20598, deterministic and
  tree-wide;
- Maloo's bare *"sessions will be run"* announcement;
- **our own `Uploaded patch set N`** — a push emits 18 at once and none is news.

Everything else wakes you, with AI reviews and human comments called out.

## Two bugs it had, both worth remembering

**It matched `Verified-1` anywhere in the message.** Gerrit's push notice reads
*"Outdated Votes: Verified+1, Verified-1"* — votes being **removed**. So the
round-11 push reported all 18 changes as freshly `Verified-1`. Now anchored to
`^Patch Set \d+: Verified-1`.

**`CHANGES` is a literal list of change numbers.** A change pushed and not
added there is invisible to the watch — which is how 68340 stayed out of the
2026-08-27 morning check until the user asked about it. Update it when the
series grows.
