/*
 * 68159 0aaa4e59 -- a torn trusted.link makes the object a non-match.
 *
 * find_device_prefilter() breaks out of its name loop when
 * scan_linkea_entry() cannot read entry i, and falls through to `return 1`
 * -- a rejection.  The nr == 0 branch six lines above calls the same
 * condition undecided (2).  This drives the real function over hand-built
 * linkea buffers; the functions are cut out of the tree by lift.py, not
 * retyped, so the two arms differ only in which tree they came from.
 *
 * Return codes: 0 accept and gather, 1 reject, 2 undecided.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fnmatch.h>
#include <sys/stat.h>
#include <linux/limits.h>
#include <lustre/lustreapi.h>
#include "lustreapi_internal.h"

#include "lifted.inc"

#define LEH_SIZE  sizeof(struct link_ea_header)
#define LEE_SIZE  sizeof(struct link_ea_entry)

static unsigned char buf[4096];

/*
 * Build a linkea.  @claimed goes in leh_reccount and @names are spelled in
 * order; @len is the xattr size the record reports.
 *
 * scan_linkea_entry() caps leh_reccount by the SMALLEST entry that could
 * fit -- (len - header) / sizeof(entry) -- so a torn buffer needs room for
 * @claimed minimum-sized entries while the entries actually in it are long
 * enough to run off the end.  A short first name caps nr instead and the
 * loop never runs, which is not the case under test.
 */
static size_t linkea_build(unsigned int claimed, const char **names,
			   unsigned int count, size_t len)
{
	struct link_ea_header *leh = (void *)buf;
	size_t off = LEH_SIZE;
	unsigned int i;

	memset(buf, 0, sizeof(buf));
	leh->leh_magic = LINK_EA_MAGIC;
	leh->leh_reccount = claimed;
	for (i = 0; i < count; i++) {
		struct link_ea_entry *lee = (void *)(buf + off);
		size_t nl = strlen(names[i]);
		size_t reclen = LEE_SIZE + nl;

		lee->lee_reclen[0] = (reclen >> 8) & 0xff;
		lee->lee_reclen[1] = reclen & 0xff;
		memcpy(lee->lee_name, names[i], nl);
		off += reclen;
	}
	leh->leh_len = off;
	return len ? len : off;
}

/* A name long enough that the entry holding it spans @mult entry slots. */
static const char *longname(char *dst, size_t mult, char pad)
{
	size_t n = LEE_SIZE * mult;

	memset(dst, pad, n);
	dst[n] = '\0';
	return dst;
}

static int pass, fail;

static void arm(const char *what, int got, int want)
{
	if (got == want) {
		printf("  PASS  %s (%d)\n", what, got);
		pass++;
	} else {
		printf("  FAIL  %s: got %d, want %d\n", what, got, want);
		fail++;
	}
}

int main(void)
{
	static const char *names[] = { "alpha", "beta", "gamma" };
	char big[256];
	const char *torn[1];
	struct llapi_scan_rec rec;
	struct find_param param;
	size_t len;
	int checked;
	int rc;

	printf("=== find_device_prefilter() over a linkea\n");

	/*
	 * Torn: the header claims three names and the buffer has room for
	 * three minimum-sized entries, but the one entry in it is long
	 * enough that entry 1 starts past the end.
	 */
	torn[0] = longname(big, 2, 'a');
	len = linkea_build(3, torn, 1, LEH_SIZE + 3 * LEE_SIZE);

	memset(&rec, 0, sizeof(rec));
	rec.lfsr_linkea = buf;
	rec.lfsr_linkeasize = len;
	rec.lfsr_valid = LLAPI_SCAN_LINKEA;
	rec.lfsr_stx.stx_mask = STATX_TYPE;
	rec.lfsr_stx.stx_mode = S_IFREG | 0644;

	/* the premise, asserted before anything is read into it */
	arm("nr is 3 on the torn buffer",
	    scan_linkea_entry(buf, len, 0, NULL, 0, NULL), 3);
	{
		char nm[NAME_MAX + 1];

		arm("entry 0 is readable",
		    scan_linkea_entry(buf, len, 0, nm, sizeof(nm), NULL), 3);
		arm("entry 1 is not",
		    scan_linkea_entry(buf, len, 1, nm, sizeof(nm), NULL), 0);
	}

	/* -name against a pattern the one readable name does not match */
	memset(&param, 0, sizeof(param));
	param.fp_pattern = "zulu";
	checked = 0;
	rc = find_device_prefilter(&rec, &param, &checked);
	arm("torn linkea, -name zulu -> undecided", rc, 2);

	/* the same, but -type rejects it outright: decided, not undecided */
	memset(&param, 0, sizeof(param));
	param.fp_pattern = "zulu";
	param.fp_type = S_IFDIR;
	checked = 0;
	rc = find_device_prefilter(&rec, &param, &checked);
	arm("torn linkea, but -type d rejects -> reject", rc, 1);

	/* a readable name that matches still accepts, torn tail or not */
	memset(&param, 0, sizeof(param));
	param.fp_pattern = "aaa*";
	checked = 0;
	rc = find_device_prefilter(&rec, &param, &checked);
	arm("torn linkea, -name matches entry 0 -> accept", rc, 0);

	/* intact: three names spelled and counted, none matching, a real miss */
	len = linkea_build(3, names, 3, 0);
	rec.lfsr_linkeasize = len;
	memset(&param, 0, sizeof(param));
	param.fp_pattern = "zulu";
	checked = 0;
	rc = find_device_prefilter(&rec, &param, &checked);
	arm("intact linkea, no name matches -> reject", rc, 1);

	memset(&param, 0, sizeof(param));
	param.fp_pattern = "gamma";
	checked = 0;
	rc = find_device_prefilter(&rec, &param, &checked);
	arm("intact linkea, last name matches -> accept", rc, 0);

	printf("=== %d pass, %d fail\n", pass, fail);
	return fail != 0;
}
