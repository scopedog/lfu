#!/usr/bin/env python3
# 10-13, after lreview run4 on 68159: the lfsp_stats copy-out moves to out:
# so a skipped device answers zeros, and the kernel-doc stops listing
# lfsp_stats as overwritten.  Idempotent, any version.  Usage: edits2.py <pfind.c>
import sys
p = sys.argv[1]; s = open(p).read()
OLD = '''	/*
	 * The scan's counters, so a program can see a partial answer and
	 * not only a message: ss_skipped is what could not be read.
	 * ss_emitted counts the records the search judged, not its matches.
	 */
	if (ustats != NULL) {
		__u32 size = ustats->ss_size;

		if (size > sizeof(stats))
			size = sizeof(stats);
		size = scan_stats_whole(size);
		stats.ss_size = size;
		memcpy(ustats, &stats, size);
		stats.ss_size = sizeof(stats);
	}
'''
NEW = '''	/*
	 * The scan's counters, so a program can see a partial answer and
	 * not only a message: ss_skipped is what could not be read.
	 * ss_emitted counts the records the search judged, not its matches.
	 * Here, so a target that was skipped answers zeros and not the
	 * counters of the caller's previous call.
	 */
	if (ustats != NULL) {
		__u32 size = ustats->ss_size;

		if (size > sizeof(stats))
			size = sizeof(stats);
		size = scan_stats_whole(size);
		stats.ss_size = size;
		memcpy(ustats, &stats, size);
	}
'''
i = s.index('\nint llapi_find_device(')
head, f = s[:i], s[i:]
if NEW not in f:
    assert f.count(OLD) == 1, 'old block'
    f = f.replace(OLD, '')
    j = f.index('\nout:\n') + len('\nout:\n')
    f = f[:j] + NEW + f[j:]
V1 = ''' * Four fields are the search's to decide and are overwritten whatever the
 * caller set: lfsp_want (the predicates decide it), lfsp_thread_count,
 * lfsp_stats and lfsp_filter.  lfsp_filter goes because this function has
 * no void *data of its own to give it: the scan carries find's state, and a
 * caller's callback would be handed that and read it as its own context.
'''
V1N = ''' * Three fields are the search's to decide and are overwritten whatever the
 * caller set: lfsp_want (the predicates decide it), lfsp_thread_count
 * and lfsp_filter.  lfsp_filter goes because this function has
 * no void *data of its own to give it: the scan carries find's state, and a
 * caller's callback would be handed that and read it as its own context.
 * lfsp_stats is filled as llapi_scan_device() fills it.
'''
V2 = ''' * Five fields are the search's to decide and are overwritten whatever the
 * caller set: lfsp_want (the predicates decide it), lfsp_thread_count,
 * lfsp_stats, lfsp_filter and lfsp_got.  lfsp_filter goes because this
 * function has no void *data of its own to give it: the scan carries find's
 * state, and a caller's callback would be handed that and read it as its own
 * context.
'''
V2N = ''' * Four fields are the search's to decide and are overwritten whatever the
 * caller set: lfsp_want (the predicates decide it), lfsp_thread_count,
 * lfsp_filter and lfsp_got.  lfsp_filter goes because this
 * function has no void *data of its own to give it: the scan carries find's
 * state, and a caller's callback would be handed that and read it as its own
 * context.  lfsp_stats is filled as llapi_scan_device() fills it.
'''
if V1N not in head and V2N not in head:
    if V1 in head:
        head = head.replace(V1, V1N)
    else:
        assert head.count(V2) == 1, 'kernel-doc'
        head = head.replace(V2, V2N)
open(p, 'w').write(head + f)
