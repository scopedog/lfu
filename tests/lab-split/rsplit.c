/*
 * One MDT's Object Stream by raw LL_IOC_LFU_SCAN, timing each ioctl.
 * rsplit MOUNT [parse]: with "parse", walk every record as the library
 * would before handing it on (header check + reclen step), timed apart.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <lustre/lustreapi.h>
#include <linux/lustre/lustre_idl.h>
#include <linux/lustre/lustre_lfu.h>

#define BUFLEN (1 << 20)

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	int parse = argc > 2 && strcmp(argv[2], "parse") == 0;
	unsigned long rpcs = 0, pages = 0, recs = 0, bytes = 0;
	double t_ioctl = 0, t_parse = 0, t0, t1, tmax = 0, tmin = 1e9;
	struct lfu_scan sc = { 0 };
	char *buf;
	int fd;

	fd = open(argv[1], O_RDONLY | O_DIRECTORY);
	if (fd < 0 || posix_memalign((void **)&buf, 4096, BUFLEN)) {
		perror("open");
		return 1;
	}
	sc.lsc_buf = (__u64)(uintptr_t)buf;
	sc.lsc_buflen = BUFLEN;

	double start = now();
	do {
		t0 = now();
		if (ioctl(fd, LL_IOC_LFU_SCAN, &sc) < 0) {
			perror("LL_IOC_LFU_SCAN");
			return 1;
		}
		t1 = now();
		t_ioctl += t1 - t0;
		if (t1 - t0 > tmax)
			tmax = t1 - t0;
		if (t1 - t0 < tmin)
			tmin = t1 - t0;
		rpcs++;
		pages += sc.lsc_npages;
		for (__u32 p = 0; p < sc.lsc_npages; p++) {
			const struct lu_idxpage *lip = (const void *)
				(buf + (size_t)p * LU_PAGE_SIZE);

			recs += lip->lip_nr;
			if (!parse)
				continue;
			t0 = now();
			const char *e = lip->lip_entries;
			for (__u16 i = 0; i < lip->lip_nr; i++) {
				const struct lfu_rec *lr = (const void *)e;

				bytes += lr->lr_reclen;
				e += lr->lr_reclen;
			}
			t_parse += now() - t0;
		}
	} while (sc.lsc_hash != LFU_SCAN_END);
	double wall = now() - start;

	printf("wall %.4f ioctl %.4f parse %.4f rpcs %lu pages %lu recs %lu "
	       "recbytes %lu ioctl_min_ms %.3f ioctl_max_ms %.3f\n",
	       wall, t_ioctl, t_parse, rpcs, pages, recs, bytes,
	       tmin * 1e3, tmax * 1e3);
	return 0;
}
