/* One LL_IOC_LFU_SCAN on MDT0000, to test the client's capability check
 * without llapi_scan_mount()'s own MDT lookup in front of it.
 * Build: gcc -O2 -I<tree>/include/uapi -o scanioctl scanioctl.c
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <linux/lustre/lustre_lfu.h>

int main(int argc, char **argv)
{
	struct lfu_scan sc = { 0 };
	void *buf;
	int fd;

	fd = open(argc > 1 ? argv[1] : "/mnt/lustre", O_RDONLY | O_DIRECTORY);
	if (fd < 0 || posix_memalign(&buf, 4096, 1 << 20)) {
		perror("open");
		return 2;
	}
	sc.lsc_buf = (unsigned long)buf;
	sc.lsc_buflen = 1 << 20;
	if (ioctl(fd, LL_IOC_LFU_SCAN, &sc) < 0) {
		printf("ioctl: %s\n", strerror(errno));
		return 1;
	}
	printf("ioctl: ok, %u pages\n", sc.lsc_npages);
	return 0;
}
