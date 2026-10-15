# lreview on 68726': the arena keeps a cursor (O(1) per allocation however
# many chunks a batch of wide layouts needs); a note where a field is added;
# an ERRORS section; test18 holds its window for seconds, not 200 ms.
B = 'lustre/utils/liblustreapi_scan_batch.c'
R = {
B: [
("""	bool				  sb_nomem;	/* a copy could not */
	struct scan_arena_chunk		 *sb_arena;
};
""",
"""	bool				  sb_nomem;	/* a copy could not */
	struct scan_arena_chunk		 *sb_arena;
	struct scan_arena_chunk		 *sb_cur;	/* being filled */
};
"""),
("""	/*
	 * The whole list is searched, not just the head: after a reset the
	 * chunks are empty but in no particular order, and a batch big
	 * enough to need a second chunk needs it again next time.  The list
	 * is a handful of entries -- one per SCAN_ARENA_CHUNK of payload in
	 * the largest batch so far -- so this is a walk of two or three.
	 */
	for (c = b->sb_arena; c != NULL; c = c->ac_next) {
		if (c->ac_used + len <= c->ac_cap) {
			p = c->ac_data + c->ac_used;
			c->ac_used += len;
			return p;
		}
	}

	cap = len > SCAN_ARENA_CHUNK ? len : SCAN_ARENA_CHUNK;
	c = malloc(sizeof(*c) + cap);
	if (c == NULL) {
		b->sb_nomem = true;
		return NULL;
	}
	c->ac_cap = cap;
	c->ac_used = len;
	c->ac_next = b->sb_arena;
	b->sb_arena = c;
	return c->ac_data;
""",
"""	/*
	 * The chunks fill in list order from sb_cur, which a reset rewinds
	 * to the head: the chunks before it are full and the ones after it
	 * empty, so an allocation does not walk the full ones however many
	 * chunks a batch of widely striped layouts needs.  A new chunk goes
	 * in after the cursor, where the next batch finds it in order.
	 */
	for (c = b->sb_cur; c != NULL; c = c->ac_next) {
		if (c->ac_used + len <= c->ac_cap) {
			b->sb_cur = c;
			p = c->ac_data + c->ac_used;
			c->ac_used += len;
			return p;
		}
	}

	cap = len > SCAN_ARENA_CHUNK ? len : SCAN_ARENA_CHUNK;
	c = malloc(sizeof(*c) + cap);
	if (c == NULL) {
		b->sb_nomem = true;
		return NULL;
	}
	c->ac_cap = cap;
	c->ac_used = len;
	if (b->sb_cur == NULL) {
		c->ac_next = b->sb_arena;
		b->sb_arena = c;
	} else {
		c->ac_next = b->sb_cur->ac_next;
		b->sb_cur->ac_next = c;
	}
	b->sb_cur = c;
	return c->ac_data;
"""),
("""	for (c = b->sb_arena; c != NULL; c = c->ac_next)
		c->ac_used = 0;
	b->sb_count = 0;
""",
"""	for (c = b->sb_arena; c != NULL; c = c->ac_next)
		c->ac_used = 0;
	b->sb_cur = b->sb_arena;
	b->sb_count = 0;
"""),
],
'include/lustre/lustreapi.h': [(
""" * arrives that way too.
 */
struct llapi_scan_rec {
""",
""" * arrives that way too.
 *
 * A pointer field added here must also be copied by scan_batch_append(),
 * or a batch hands it out pointing into a buffer the scan has reused.
 */
struct llapi_scan_rec {
""")],
'Documentation/man3/llapi_scan_next.3': [(
""".SH NOTES
""",
""".SH ERRORS
.TP 15
.B -EINVAL
.B llapi_scan_namespace_open()
was given a NULL
.I path
or
.IR hp ,
or a parameter block
.BR llapi_scan_namespace (3)
refuses;
.B llapi_scan_next()
was given a NULL handle,
.I recs
or
.IR nrecs .
.I recs
and
.I nrecs
are left as they were.
.TP 15
.B -ENOMEM
the handle, its batches or a record's copy could not be allocated.
.TP 15
.B -EBUSY
another thread is inside
.B llapi_scan_next()
on this handle;
.I recs
and
.I nrecs
are left as they were, and
.B llapi_scan_close()
frees nothing.
.SH NOTES
""")],
'lustre/tests/llapi_scan_test.c': [(
"""	if (n == 4) {
		sem_post(&t18_rejecting);
		usleep(200000);
	}
""",
"""	/* long enough that only a close that does not stop the walk lets the
	 * next object through, even on a loaded test node
	 */
	if (n == 4) {
		sem_post(&t18_rejecting);
		sleep(3);
	}
""")],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
