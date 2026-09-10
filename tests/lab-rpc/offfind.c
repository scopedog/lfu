/* The offloaded arm: pull one MDT's Object Stream over LL_IOC_LFU_SCAN and
 * apply "-mtime -1 -type f" to the records, counting matches.  The predicate
 * is the whole point of the comparison, so it is spelled out here rather
 * than reached through liblustreapi: this is a spike harness, and its answer
 * is checked against lfind's real predicate on the server. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <linux/types.h>
#include <linux/lustre/lustre_idl.h>
#include <linux/lustre/lustre_lfu.h>
int main(int argc, char **argv) {
	const char *mnt = argv[1];
	unsigned mdt = argc > 2 ? atoi(argv[2]) : 0;
	int quiet = argc > 3;
	int fd = open(mnt, O_RDONLY | O_DIRECTORY);
	if (fd < 0) { perror("open"); return 1; }
	size_t buflen = 1 << 20;
	char *buf = aligned_alloc(4096, buflen);
	struct lfu_scan sc = { .lsc_mdt_index = mdt, .lsc_hash = 0,
			       .lsc_buf = (uintptr_t)buf, .lsc_buflen = buflen };
	time_t cutoff = time(NULL) - 86400;	/* -mtime -1 */
	unsigned long calls = 0, recs = 0, match = 0, bytes = 0;
	for (;;) {
		if (ioctl(fd, LL_IOC_LFU_SCAN, &sc) < 0) {
			fprintf(stderr, "LL_IOC_LFU_SCAN: %s\n", strerror(errno));
			return 2;
		}
		calls++;
		for (unsigned p = 0; p < sc.lsc_npages; p++) {
			struct lu_idxpage *lip = (void *)(buf + p * LU_PAGE_SIZE);
			if (lip->lip_magic != LIP_MAGIC) return 3;
			const char *e = lip->lip_entries;
			for (unsigned i = 0; i < lip->lip_nr; i++) {
				const struct lfu_rec *r = (const void *)e;
				recs++; bytes += r->lr_reclen;
				if (S_ISREG(r->lr_mode) && r->lr_mtime > cutoff)
					match++;
				e += r->lr_reclen;
			}
		}
		if (sc.lsc_hash == LFU_SCAN_END) break;
	}
	if (!quiet)
		fprintf(stderr, "match=%lu recs=%lu calls=%lu bytes=%lu (%.0f recs/RPC)\n",
			match, recs, calls, bytes, (double)recs/calls);
	printf("%lu\n", match);
	return 0;
}
