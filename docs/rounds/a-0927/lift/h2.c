#include <stdio.h>
#include <stdbool.h>
#include <string.h>
typedef unsigned long long __u64;
#define SCAN_CL_CLEAR_BATCH 1000
#define LLAPI_SCAN_CL_F_CLEAR 1
#define LLAPI_MSG_ERROR 0
struct list_head { struct list_head *next, *prev; };
struct llapi_scan_changelog_param { int sc_flags; const char *sc_mdtname, *sc_user; };
struct scan_cl_obj { struct list_head co_link; __u64 co_first; };
struct scan_cl { const struct llapi_scan_changelog_param *sl_param; struct list_head sl_aged;
	__u64 sl_last_cleared, sl_clear_walked, sl_accepted; };
static long walks, clears;
/* one cached object, counted as one walk step per iteration */
static struct scan_cl_obj B;
#define list_for_each_entry(o, head, m) \
	for (walks++, o = &B; o; o = NULL)
static int llapi_changelog_clear(const char *m, const char *u, __u64 e) { clears++; return 0; }
static void llapi_error(int l, int rc, const char *f, ...) {}
#include ARM_HELD
#include ARM_CLEAR
int main(void) {
	struct llapi_scan_changelog_param sc = { LLAPI_SCAN_CL_F_CLEAR, "m", "u" };
	struct scan_cl sl = { &sc };
	__u64 i;
	/* B held from record 10: pins the clear point at 9 */
	B.co_first = 0; /* empty-ish: held_first returns 0 */
	for (i = 1; i <= 100000; i++) { sl.sl_accepted = i; scan_cl_clear(&sl, false); }
	printf("records=100000 walks=%ld clears=%ld last_cleared=%llu\n", walks, clears, sl.sl_last_cleared);
	return 0;
}
