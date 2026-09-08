/* Does llapi_scan_namespace() fill lfsp_stats, and does the accounting add up? */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <lustre/lustreapi.h>

static int seen;
static int cb(const struct llapi_scan_rec *rec, void *data)
{
	seen++;
	return 0;
}
/* reject every third object, so ss_filtered is not trivially zero */
static int filt(const struct llapi_scan_rec *rec, void *data)
{
	static int n;
	return (++n % 3) == 0 ? 1 : 0;
}

int main(int argc, char **argv)
{
	struct llapi_scan_stats st = { .ss_size = sizeof(st) };
	struct llapi_scan_param sp = { .lfsp_size = sizeof(sp) };
	unsigned long long sum = 0;
	int rc, i;

	sp.lfsp_stats = &st;
	if (argc > 2 && argv[2][0] == 'f')
		sp.lfsp_filter = filt;
	if (argc > 3)
		sp.lfsp_thread_count = atoi(argv[3]);
	rc = llapi_scan_namespace(argv[1], &sp, cb, NULL);
	printf("rc=%d  threads=%u  cb called %d\n", rc, sp.lfsp_thread_count, seen);
	printf("ss_size=%u seen=%llu emitted=%llu filtered=%llu skipped=%llu\n",
	       st.ss_size, (unsigned long long)st.ss_seen,
	       (unsigned long long)st.ss_emitted,
	       (unsigned long long)st.ss_filtered,
	       (unsigned long long)st.ss_skipped);
	for (i = 0; i < LLAPI_SCAN_CLS_MAX; i++)
		sum += st.ss_class[i];
	printf("sum(ss_class)=%llu  visible=%llu\n", sum,
	       (unsigned long long)st.ss_class[LLAPI_SCAN_CLS_VISIBLE]);
	printf("accounting: seen == filtered + skipped + sum(class)? %s\n",
	       st.ss_seen == st.ss_filtered + st.ss_skipped + sum ? "YES" : "NO");
	printf("emitted == cb calls? %s\n",
	       st.ss_emitted == (unsigned long long)seen ? "YES" : "NO");
	return 0;
}
