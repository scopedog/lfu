# AI on 68726 PS5 9954f2b7: if the helper enters llapi_scan_next() first,
# the guard refuses THIS thread; that is the guard working, not a failure.
R = {
'lustre/tests/llapi_scan_test.c': [(
"""	pthread_join(th, NULL);
	ASSERTF(rc >= 0, "the slow scan's third batch failed: %d", rc);

	if (between(&br.br_when, &t0, &t1))
""",
"""	pthread_join(th, NULL);
	/* the helper got in first: the guard refused this thread instead */
	if (rc == -EBUSY && br.br_rc >= 0)
		printf("      (the second call won the race; refused here)\\n");
	else if (rc < 0)
		DIE("the slow scan's third batch failed: %d", rc);
	else if (between(&br.br_when, &t0, &t1))
""")],
}
def fn(path, s, subj):
    for o, n in R.get(path, []):
        if o in s:
            s = s.replace(o, n)
    return s
