# Lift-and-compare harnesses

A harness that retypes a function tests the copy, not the code. `lift.py`
cuts named functions out of the tree's real sources, comments and all, and
writes them to `lifted.inc`; the harness `#include`s that. Point it at a
second tree — a worktree, or a `git show HEAD:<file>` dump — and the same
harness runs the unfixed text, which is the only way an arm proves a fix
rather than restating it.

    python3 lift.py <tree> lifted.inc
    gcc -g -O0 -D_GNU_SOURCE -I<tree>/lustre/utils -I<tree>/include \
        -I<tree>/include/uapi -include <tree>/config.h \
        -o harness linkea_torn.c

## `linkea_torn.c` — 68159 `0aaa4e59`

Drives `find_device_prefilter()` over hand-built `trusted.link` buffers. A
torn linkea — `leh_reccount` claiming more names than the buffer spells —
used to make the object a **non-match** where the no-name case beside it
counts the same condition undecided.

**Unfixed 7 pass / 1 fail, fixed 8 / 0.**

The fixture is the fiddly part: `scan_linkea_entry()` caps `leh_reccount` by
the *smallest* entry that could fit, so a short first name caps `nr` to 1 and
the loop under test never runs. The buffer needs room for `claimed`
minimum-sized entries while the entries actually in it are long enough to run
off the end. The first three arms assert that premise before anything reads
into it.
