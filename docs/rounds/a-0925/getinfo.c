/* getinfo: rdev of NAME in DIR from stat(2), IOC_MDC_GETFILEINFO_V1 and _V2 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <linux/lustre/lustre_user.h>

int main(int argc, char **argv)
{
	char *buf = calloc(1, 65536);
	struct stat st;
	int dfd, i;

	if (argc < 3)
		return 2;
	dfd = open(argv[1], O_RDONLY | O_DIRECTORY);
	if (dfd < 0)
		return 1;
	for (i = 2; i < argc; i++) {
		struct lov_user_mds_data_v1 *v1 = (void *)buf;
		struct lov_user_mds_data *v2 = (void *)buf;
		unsigned long long r1;
		unsigned int m2, n2;

		fstatat(dfd, argv[i], &st, AT_SYMLINK_NOFOLLOW);
		memset(buf, 0, 65536);
		strcpy(buf, argv[i]);
		if (ioctl(dfd, IOC_MDC_GETFILEINFO_V1, buf) < 0) {
			perror("V1");
			return 1;
		}
		r1 = v1->lmd_st.st_rdev;
		memset(buf, 0, 65536);
		strcpy(buf, argv[i]);
		if (ioctl(dfd, IOC_MDC_GETFILEINFO_V2, buf) < 0) {
			perror("V2");
			return 1;
		}
		m2 = v2->lmd_stx.stx_rdev_major;
		n2 = v2->lmd_stx.stx_rdev_minor;
		printf("%-12s stat=%u:%u  V1 st_rdev=%#llx (major()=%u minor()=%u)  V2=%u:%u\n",
		       argv[i], major(st.st_rdev), minor(st.st_rdev), r1,
		       major(r1), minor(r1), m2, n2);
	}
	return 0;
}
