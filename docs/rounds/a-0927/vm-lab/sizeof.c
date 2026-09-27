/* 09-27: sizeof(struct llapi_scan_stats) against one arm's header */
#include <stdio.h>
#include <stddef.h>
#include <lustre/lustreapi.h>

int main(void)
{
	printf("sizeof(struct llapi_scan_stats)=%zu ss_class=%zu entries, offsetof(ss_class)=%zu, LLAPI_SCAN_CLS_MAX=%d\n",
	       sizeof(struct llapi_scan_stats),
	       sizeof(((struct llapi_scan_stats *)0)->ss_class) / sizeof(__u64),
	       offsetof(struct llapi_scan_stats, ss_class), LLAPI_SCAN_CLS_MAX);
	return 0;
}
