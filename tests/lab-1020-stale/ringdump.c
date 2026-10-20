/* Read one target's Object Stream from /dev/lfu_scan.  Prints one line per
 * record, "seq:oid:ver mode name parent", then the LFU_IOC_STATS counters.
 * Build: gcc -O2 -I<tree>/include/uapi -o ringdump ringdump.c
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/lustre/lustre_lfu.h>

static void name_of(const struct lfu_rec *lr, char *name, size_t len,
		    unsigned long long *pseq, unsigned int *poid)
{
	const unsigned char *l = lfu_rec_link(lr);
	unsigned int reclen;

	snprintf(name, len, "-");
	*pseq = 0;
	*poid = 0;
	/* link_ea_header is 24 bytes, then lee_reclen[2] (BE), 16-byte BE fid */
	if (!(lr->lr_lfu & LFU_REC_HAVE_LINK) || lr->lr_linklen < 24 + 18)
		return;
	l += 24;
	reclen = (l[0] << 8) | l[1];
	if (reclen < 18 || 24 + reclen > lr->lr_linklen)
		return;
	for (int i = 0; i < 8; i++)
		*pseq = (*pseq << 8) | l[2 + i];
	*poid = (l[10] << 24) | (l[11] << 16) | (l[12] << 8) | l[13];
	snprintf(name, len, "%.*s", (int)(reclen - 18), (const char *)l + 18);
}

int main(int argc, char **argv)
{
	static char buf[1 << 20];
	struct lfu_target lt = { { 0 } };
	struct lfu_stats st;
	unsigned long long n = 0;
	ssize_t got;
	int fd;

	if (argc != 2) {
		fprintf(stderr, "usage: %s fsname-MDT0000\n", argv[0]);
		return 2;
	}
	fd = open("/dev/" LFU_DEVNAME, O_RDONLY);
	if (fd < 0) {
		perror("open");
		return 1;
	}
	snprintf(lt.lt_name, sizeof(lt.lt_name), "%s", argv[1]);
	if (ioctl(fd, LFU_IOC_TARGET, &lt) < 0) {
		perror("LFU_IOC_TARGET");
		return 1;
	}
	while ((got = read(fd, buf, sizeof(buf))) > 0) {
		const struct lfu_rec *lr = (const struct lfu_rec *)buf;
		const char *end = buf + got;

		while ((const char *)lr < end) {
			unsigned long long pseq;
			unsigned int poid;
			char name[256];

			name_of(lr, name, sizeof(name), &pseq, &poid);
			printf("0x%llx:0x%x:0x%x %o %s 0x%llx:0x%x %llu\n",
			       (unsigned long long)lr->lr_fid_seq,
			       lr->lr_fid_oid, lr->lr_fid_ver, lr->lr_mode,
			       name, pseq, poid,
			       (unsigned long long)lr->lr_oid);
			n++;
			lr = lfu_rec_next(lr);
		}
	}
	if (got < 0) {
		perror("read");
		return 1;
	}
	memset(&st, 0, sizeof(st));
	if (ioctl(fd, LFU_IOC_STATS, &st) < 0) {
		perror("LFU_IOC_STATS");
		return 1;
	}
	fprintf(stderr, "STATS records=%llu seen=%llu emitted=%llu raw=%llu fallback=%llu xa_inline=%llu xa_ext=%llu xa_iget=%llu stale_slot=%llu err=%d\n",
		n, st.ls_seen, st.ls_emitted, st.ls_raw, st.ls_fallback,
		st.ls_xa_inline, st.ls_xa_ext, st.ls_xa_iget,
		/* ls_reserved2[0] on the old arm, ls_stale on the new */
		*(unsigned long long *)((char *)&st.ls_link_big + 8), st.ls_err);
	return 0;
}
