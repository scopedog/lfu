// SPDX-License-Identifier: LGPL-2.1+
/*
 * LFU filter compiler — lfs find syntax in, struct lfu_filter out.  See
 * lfu_filter.h for the design and docs/filter-levels.md for why the tiers,
 * the demand mask and the unknown outcome all have to exist.
 *
 * Userspace only: this is where getopt tables, strtoull(), getpwnam() and
 * error messages live.  The per-object evaluation is lfu_filter_eval.c, which
 * has none of those so it can also be built into the kernel.  Nothing here may
 * include a device library header: this file is linked into every backend.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <pwd.h>
#include <grp.h>
#include <sys/stat.h>

#include "lfu_filter.h"
#include "lfu_scan.h"

/* ------------------------------------------------------------------ */
/* Option table                                                       */

const struct option lfu_filter_options[] = {
	{ "atime",		required_argument, NULL, LFU_OPT_ATIME },
	{ "mtime",		required_argument, NULL, LFU_OPT_MTIME },
	{ "ctime",		required_argument, NULL, LFU_OPT_CTIME },
	{ "btime",		required_argument, NULL, LFU_OPT_BTIME },
	{ "crtime",		required_argument, NULL, LFU_OPT_BTIME },
	{ "uid",		required_argument, NULL, LFU_OPT_UID },
	{ "user",		required_argument, NULL, LFU_OPT_UID },
	{ "gid",		required_argument, NULL, LFU_OPT_GID },
	{ "group",		required_argument, NULL, LFU_OPT_GID },
	{ "type",		required_argument, NULL, LFU_OPT_TYPE },
	{ "perm",		required_argument, NULL, LFU_OPT_PERM },
	{ "links",		required_argument, NULL, LFU_OPT_LINKS },
	{ "projid",		required_argument, NULL, LFU_OPT_PROJID },
	{ "attrs",		required_argument, NULL, LFU_OPT_ATTRS },
	{ "dev-blocks",		required_argument, NULL, LFU_OPT_DEV_BLOCKS },
	{ "size",		required_argument, NULL, LFU_OPT_SIZE },
	{ "blocks",		required_argument, NULL, LFU_OPT_BLOCKS },
	{ "stripe-count",	required_argument, NULL, LFU_OPT_STRIPE_COUNT },
	{ "stripe-size",	required_argument, NULL, LFU_OPT_STRIPE_SIZE },
	{ "stripe-index",	required_argument, NULL, LFU_OPT_OST },
	{ "ost",		required_argument, NULL, LFU_OPT_OST },
	{ "pool",		required_argument, NULL, LFU_OPT_POOL },
	{ "layout",		required_argument, NULL, LFU_OPT_LAYOUT },
	{ "mirror-count",	required_argument, NULL, LFU_OPT_MIRROR_COUNT },
	{ "component-count",	required_argument, NULL, LFU_OPT_COMP_COUNT },
	{ "comp-count",		required_argument, NULL, LFU_OPT_COMP_COUNT },
	{ "mdt-count",		required_argument, NULL, LFU_OPT_MDT_COUNT },
	{ "mdt-hash",		required_argument, NULL, LFU_OPT_MDT_HASH },
	{ "name",		required_argument, NULL, LFU_OPT_NAME },
	{ NULL, 0, NULL, 0 }
};

/*
 * Help text.  The spellings are lfs find's, deliberately: LFU replaces that
 * command, so a filter that works there must work here with the same words.
 * --dev-blocks is the one addition, and it exists because `--blocks` had to be
 * given lfs find's meaning; see the note below.
 */
const char *const lfu_filter_usage =
"\n"
"Filters (lfs find vocabulary; `!` before an option negates it, `+` means\n"
"more than, `-` less than, no sign means equal):\n"
"      --atime|--mtime|--ctime|--btime [+-]N[smhdwy]\n"
"                          age of the object; days if no unit given\n"
"      --uid|--user ID|NAME     --gid|--group ID|NAME\n"
"      --type f|d|l|b|c|p|s     --perm [/-]MODE      --links [+-]N\n"
"      --projid N               --attrs [^]ATTR[,...]  (c,i,a,d,E)\n"
"      --size [+-]N[bcKMGTPE]   the file's size    — tier 1, via trusted.som\n"
"      --blocks [+-]N[bcKMGTPE] the file's blocks  — tier 1, via trusted.som\n"
"      --dev-blocks [+-]N       blocks this target's own inode/dnode uses\n"
"      --stripe-count|--stripe-size|--mirror-count|--comp-count [+-]N\n"
"      --ost|--stripe-index IDX[,IDX...]   --pool NAME\n"
"      --layout released,raid0,mdt         --name PATTERN\n"
"      --mdt-count [+-]N        --mdt-hash NAME|N   (striped directories)\n"
"\n"
"An MDT-only scan is `lfs find --lazy` by construction: --size/--blocks read\n"
"trusted.som, so for a striped file never closed since SOM was enabled the\n"
"answer is neither match nor no-match but unknown, and is counted as such.\n";

/* ------------------------------------------------------------------ */
/* Value parsing                                                       */

/* What does a field demand beyond the inode? */
static uint32_t lfu_field_needs(enum lfu_field f)
{
	switch (f) {
	case LFU_F_SIZE:
	case LFU_F_BLOCKS:
		/* SOM for the value, LOV to know whether the value is needed:
		 * an unstriped file's i_size is authoritative (§4).
		 */
		return LFU_NEED_SOM | LFU_NEED_LOV;
	case LFU_F_STRIPE_COUNT:
	case LFU_F_STRIPE_SIZE:
	case LFU_F_OST:
	case LFU_F_POOL:
	case LFU_F_LAYOUT:
	case LFU_F_MIRROR_COUNT:
	case LFU_F_COMP_COUNT:
		return LFU_NEED_LOV;
	case LFU_F_MDT_COUNT:
	case LFU_F_MDT_HASH:
		return LFU_NEED_LMV;
	case LFU_F_NAME:
		return LFU_NEED_LINK;
	default:
		return 0;
	}
}

static struct lfu_pred *lfu_pred_new(struct lfu_filter *f, enum lfu_field fld)
{
	struct lfu_pred *p;

	if (f->n == LFU_MAX_PRED) {
		fprintf(stderr, "lfu: too many filter predicates (max %d)\n",
			LFU_MAX_PRED);
		return NULL;
	}

	p = &f->p[f->n++];
	memset(p, 0, sizeof(*p));
	p->field = (uint8_t)fld;
	p->neg = f->neg_pending ? 1 : 0;
	f->neg_pending = 0;
	f->needs |= lfu_field_needs(fld);
	return p;
}

/*
 * Leading sign, lfs find's way round.  `+` is "more than", which for an age
 * means an older timestamp — the inversion find_value_cmp()
 * (liblustreapi_pfind.c:500) spells with a negative sign field.  Comparing
 * ages rather than timestamps lets us keep GT meaning GT.
 */
static const char *lfu_parse_sign(const char *arg, enum lfu_op *op)
{
	if (*arg == '+') {
		*op = LFU_OP_GT;
		return arg + 1;
	}
	if (*arg == '-') {
		*op = LFU_OP_LT;
		return arg + 1;
	}
	*op = LFU_OP_EQ;
	return arg;
}

/*
 * llapi_parse_size() (liblustreapi.c), including the fraction it accepts, so
 * that `--size +1.5G` means here what it means there.  `units` is the
 * multiplier for a bare number: 512 for sizes and blocks, 1 elsewhere.
 */
static int lfu_parse_size(const char *arg, uint64_t units, uint64_t *out)
{
	uint64_t whole, frac = 0, frac_div = 1, mult = units;
	char *end;

	errno = 0;
	whole = strtoull(arg, &end, 0);
	if (end == arg || errno != 0)
		return -1;

	if (*end == '.') {
		const char *fs = end + 1;

		frac = strtoull(fs, &end, 10);
		for (const char *q = fs; q < end; q++)
			frac_div *= 10;
	}

	if (*end != '\0') {
		switch (tolower((unsigned char)*end)) {
		case 'b': mult = 512; break;
		case 'c': mult = 1; break;
		case 'k': mult = 1ULL << 10; break;
		case 'm': mult = 1ULL << 20; break;
		case 'g': mult = 1ULL << 30; break;
		case 't': mult = 1ULL << 40; break;
		case 'p': mult = 1ULL << 50; break;
		case 'e': mult = 1ULL << 60; break;
		default:
			return -1;
		}
		if (*(end + 1) != '\0')
			return -1;
	}

	*out = whole * mult + (frac * mult) / frac_div;
	return 0;
}

/*
 * set_time() (lfs.c:6290): a sum of unit-suffixed terms, days by default, and
 * a margin equal to the smallest unit used so that an unsigned `--mtime 1d`
 * means "within that day" rather than "to the second".
 */
static int lfu_parse_time(const char *arg, uint64_t *secs, uint64_t *margin)
{
	uint64_t total = 0, small = 24 * 60 * 60;
	const char *p = arg;

	if (*p == '\0')
		return -1;

	while (*p != '\0') {
		uint64_t unit;
		uint64_t val;
		char *end;

		errno = 0;
		val = strtoull(p, &end, 0);
		if (end == p || errno != 0)
			return -1;

		switch (*end) {
		case 'y': unit = 365 * 24 * 60 * 60; end++; break;
		case 'w': unit = 7 * 24 * 60 * 60; end++; break;
		case 'd': unit = 24 * 60 * 60; end++; break;
		case 'h': unit = 60 * 60; end++; break;
		case 'm': unit = 60; end++; break;
		case 's': unit = 1; end++; break;
		case '\0': unit = 24 * 60 * 60; break;	/* days by default */
		default:
			return -1;
		}

		total += val * unit;
		if (unit < small)
			small = unit;
		p = end;
	}

	*secs = total;
	*margin = small;
	return 0;
}

static int lfu_parse_u64(const char *arg, uint64_t *out)
{
	char *end;

	errno = 0;
	*out = strtoull(arg, &end, 0);
	return (end == arg || *end != '\0' || errno != 0) ? -1 : 0;
}

/* An id, or a user/group name resolved through the local databases the way
 * lfs find resolves --user/--group.
 */
static int lfu_parse_uid(const char *arg, uint64_t *out)
{
	const struct passwd *pw;

	if (lfu_parse_u64(arg, out) == 0)
		return 0;
	pw = getpwnam(arg);
	if (pw == NULL)
		return -1;
	*out = pw->pw_uid;
	return 0;
}

static int lfu_parse_gid(const char *arg, uint64_t *out)
{
	const struct group *gr;

	if (lfu_parse_u64(arg, out) == 0)
		return 0;
	gr = getgrnam(arg);
	if (gr == NULL)
		return -1;
	*out = gr->gr_gid;
	return 0;
}

static int lfu_parse_type(const char *arg, uint64_t *out)
{
	static const struct {
		const char *name;
		char c;
		uint64_t mode;
	} types[] = {
		{ "file",	'f', S_IFREG },
		{ "dir",	'd', S_IFDIR },
		{ "link",	'l', S_IFLNK },
		{ "block",	'b', S_IFBLK },
		{ "char",	'c', S_IFCHR },
		{ "pipe",	'p', S_IFIFO },
		{ "sock",	's', S_IFSOCK },
	};

	for (size_t i = 0; i < sizeof(types) / sizeof(types[0]); i++)
		if ((arg[0] == types[i].c && arg[1] == '\0') ||
		    strcmp(arg, types[i].name) == 0) {
			*out = types[i].mode;
			return 0;
		}
	return -1;
}

/* find(1)'s --perm: MODE exact, -MODE all bits set, /MODE any bit set. */
static int lfu_parse_perm(const char *arg, enum lfu_op *op, uint64_t *out)
{
	if (*arg == '-') {
		*op = LFU_OP_ALL;
		arg++;
	} else if (*arg == '/') {
		*op = LFU_OP_ANY;
		arg++;
	} else {
		*op = LFU_OP_EQ;
	}

	errno = 0;
	char *end;
	uint64_t mode = strtoull(arg, &end, 8);

	if (end == arg || *end != '\0' || errno != 0 || mode > 07777)
		return -1;
	*out = mode;
	return 0;
}

/*
 * --attrs=[^]ATTR[,...] — attrs_array (lustreapi.h:1416).  `^` marks an
 * attribute that must be absent, so the predicate carries two masks.
 */
static int lfu_parse_attrs(const char *arg, uint64_t *want, uint64_t *nowant)
{
	static const struct {
		const char *name;
		char c;
		uint32_t bit;
	} attrs[] = {
		{ "Compressed",  'c', LFU_ATTR_COMPRESSED },
		{ "Immutable",   'i', LFU_ATTR_IMMUTABLE },
		{ "Append_Only", 'a', LFU_ATTR_APPEND },
		{ "No_Dump",     'd', LFU_ATTR_NODUMP },
		{ "Encrypted",   'E', LFU_ATTR_ENCRYPTED },
	};
	char buf[128];
	char *tok, *save = NULL;

	if (strlen(arg) >= sizeof(buf))
		return -1;
	(void)snprintf(buf, sizeof(buf), "%s", arg);

	*want = 0;
	*nowant = 0;

	for (tok = strtok_r(buf, ",", &save); tok != NULL;
	     tok = strtok_r(NULL, ",", &save)) {
		int exclude = 0;
		size_t i;

		if (*tok == '^') {
			exclude = 1;
			tok++;
		}
		for (i = 0; i < sizeof(attrs) / sizeof(attrs[0]); i++)
			if ((tok[0] == attrs[i].c && tok[1] == '\0') ||
			    strcasecmp(tok, attrs[i].name) == 0)
				break;
		if (i == sizeof(attrs) / sizeof(attrs[0])) {
			/*
			 * Automount is the one lfs find name with no device
			 * answer: ext4 spends 0x1000 on EXT4_INDEX_FL, so
			 * matching it would silently mean "indexed directory".
			 */
			if (strcasecmp(tok, "Automount") == 0 ||
			    strcmp(tok, "M") == 0)
				fprintf(stderr,
					"lfu: --attrs Automount is not derivable "
					"from a device scan\n");
			return -1;
		}
		if (exclude)
			*nowant |= attrs[i].bit;
		else
			*want |= attrs[i].bit;
	}

	return (*want == 0 && *nowant == 0) ? -1 : 0;
}

/* --ost / --stripe-index: a comma list of indices, or N-M ranges. */
static int lfu_parse_index_list(const char *arg, struct lfu_pred *p)
{
	char buf[512];
	char *tok, *save = NULL;

	if (strlen(arg) >= sizeof(buf))
		return -1;
	(void)snprintf(buf, sizeof(buf), "%s", arg);

	for (tok = strtok_r(buf, ",", &save); tok != NULL;
	     tok = strtok_r(NULL, ",", &save)) {
		uint64_t lo, hi;
		char *dash = strchr(tok, '-');
		char *end;

		errno = 0;
		lo = strtoull(tok, &end, 0);
		if (end == tok || errno != 0)
			return -1;
		if (dash != NULL && end == dash) {
			hi = strtoull(dash + 1, &end, 0);
			if (end == dash + 1 || *end != '\0' || hi < lo)
				return -1;
		} else if (*end == '\0') {
			hi = lo;
		} else {
			return -1;
		}

		for (uint64_t v = lo; v <= hi; v++) {
			if (p->nlist == LFU_MAX_LIST) {
				fprintf(stderr,
					"lfu: index list longer than %d\n",
					LFU_MAX_LIST);
				return -1;
			}
			if (v > UINT32_MAX)
				return -1;
			p->list[p->nlist++] = (uint32_t)v;
		}
	}

	return p->nlist == 0 ? -1 : 0;
}

/* --layout released,raid0,mdt — matched against the LOV pattern. */
static int lfu_parse_layout(const char *arg, uint64_t *out)
{
	char buf[64];
	char *tok, *save = NULL;
	uint64_t pat = 0;

	if (strlen(arg) >= sizeof(buf))
		return -1;
	(void)snprintf(buf, sizeof(buf), "%s", arg);

	for (tok = strtok_r(buf, ",", &save); tok != NULL;
	     tok = strtok_r(NULL, ",", &save)) {
		if (strcmp(tok, "released") == 0)
			pat |= LOV_PATTERN_F_RELEASED;
		else if (strcmp(tok, "raid0") == 0)
			pat |= LOV_PATTERN_RAID0;
		else if (strcmp(tok, "mdt") == 0)
			pat |= LOV_PATTERN_MDT;
		else if (strcmp(tok, "foreign") == 0)
			pat |= LOV_PATTERN_FOREIGN;
		else if (strcmp(tok, "overstriped") == 0)
			pat |= LOV_PATTERN_OVERSTRIPING;
		else
			return -1;
	}

	*out = pat;
	return pat == 0 ? -1 : 0;
}

static int lfu_parse_mdt_hash(const char *arg, uint64_t *out)
{
	static const char *const names[] = {
		NULL, "all_char", "fnv_1a_64", "crush", "crush2"
	};

	for (size_t i = 1; i < sizeof(names) / sizeof(names[0]); i++)
		if (strcmp(arg, names[i]) == 0) {
			*out = i;
			return 0;
		}
	return lfu_parse_u64(arg, out);
}

/* ------------------------------------------------------------------ */
/* Compile                                                             */

static int lfu_bad(const char *opt, const char *arg)
{
	fprintf(stderr, "lfu: bad %s value '%s'\n", opt, arg);
	return -2;
}

int lfu_filter_opt(struct lfu_filter *f, int opt, const char *arg)
{
	struct lfu_pred *p = NULL;
	enum lfu_op op;
	uint64_t v = 0, v2 = 0;

	switch (opt) {
	case LFU_OPT_NOT:
		f->neg_pending = 1;
		return 0;

	/* --- times: compared as ages, so + stays "more than" ------------- */
	case LFU_OPT_ATIME:
	case LFU_OPT_MTIME:
	case LFU_OPT_CTIME:
	case LFU_OPT_BTIME: {
		static const enum lfu_field map[] = {
			LFU_F_ATIME, LFU_F_MTIME, LFU_F_CTIME, LFU_F_BTIME
		};
		const char *rest = lfu_parse_sign(arg, &op);

		if (lfu_parse_time(rest, &v, &v2) != 0)
			return lfu_bad("time", arg);
		p = lfu_pred_new(f, map[opt - LFU_OPT_ATIME]);
		if (p == NULL)
			return -2;
		p->op = (uint8_t)op;
		p->val = v;
		p->val2 = v2;
		return 0;
	}

	/* --- plain numeric comparisons ---------------------------------- */
	case LFU_OPT_LINKS:
	case LFU_OPT_STRIPE_COUNT:
	case LFU_OPT_MIRROR_COUNT:
	case LFU_OPT_COMP_COUNT:
	case LFU_OPT_MDT_COUNT: {
		static const struct { int opt; enum lfu_field f; } map[] = {
			{ LFU_OPT_LINKS,	LFU_F_LINKS },
			{ LFU_OPT_STRIPE_COUNT,	LFU_F_STRIPE_COUNT },
			{ LFU_OPT_MIRROR_COUNT,	LFU_F_MIRROR_COUNT },
			{ LFU_OPT_COMP_COUNT,	LFU_F_COMP_COUNT },
			{ LFU_OPT_MDT_COUNT,	LFU_F_MDT_COUNT },
		};
		const char *rest = lfu_parse_sign(arg, &op);

		if (lfu_parse_u64(rest, &v) != 0)
			return lfu_bad("count", arg);
		for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); i++)
			if (map[i].opt == opt) {
				p = lfu_pred_new(f, map[i].f);
				break;
			}
		if (p == NULL)
			return -2;
		p->op = (uint8_t)op;
		p->val = v;
		return 0;
	}

	/* --- byte/block quantities -------------------------------------- */
	case LFU_OPT_SIZE:
	case LFU_OPT_BLOCKS:
	case LFU_OPT_DEV_BLOCKS:
	case LFU_OPT_STRIPE_SIZE: {
		/*
		 * All three quantities are compared in BYTES, and a bare
		 * number means 512-byte units for size and blocks — lfs find
		 * multiplies stx_blocks by 512 before comparing
		 * (liblustreapi_pfind.c:2971).  The unit multiplier doubles as
		 * the equality margin, so `--size 1M` means "up to 1 MiB",
		 * exactly as find_value_cmp() has it.
		 */
		uint64_t units = opt == LFU_OPT_STRIPE_SIZE ? 1 : 512;
		enum lfu_field fld =
			opt == LFU_OPT_SIZE ? LFU_F_SIZE :
			opt == LFU_OPT_BLOCKS ? LFU_F_BLOCKS :
			opt == LFU_OPT_DEV_BLOCKS ? LFU_F_DEV_BLOCKS :
			LFU_F_STRIPE_SIZE;
		const char *rest = lfu_parse_sign(arg, &op);
		uint64_t margin = units;

		if (lfu_parse_size(rest, units, &v) != 0)
			return lfu_bad("size", arg);
		if (fld == LFU_F_STRIPE_SIZE) {
			/* lfs.c:7983 — a value too small to be a valid stripe
			 * size is taken as KiB rather than rejected.
			 */
			if (v < 4096)
				v *= 1024;
			margin = 1;
		}
		p = lfu_pred_new(f, fld);
		if (p == NULL)
			return -2;
		p->op = (uint8_t)op;
		p->val = v;
		p->val2 = op == LFU_OP_EQ ? margin : 0;
		return 0;
	}

	/* --- identity and mode ------------------------------------------ */
	case LFU_OPT_UID:
	case LFU_OPT_GID:
	case LFU_OPT_PROJID: {
		enum lfu_field fld = opt == LFU_OPT_UID ? LFU_F_UID :
				     opt == LFU_OPT_GID ? LFU_F_GID :
				     LFU_F_PROJID;
		int rc = opt == LFU_OPT_UID ? lfu_parse_uid(arg, &v) :
			 opt == LFU_OPT_GID ? lfu_parse_gid(arg, &v) :
			 lfu_parse_u64(arg, &v);

		if (rc != 0)
			return lfu_bad("id", arg);
		p = lfu_pred_new(f, fld);
		if (p == NULL)
			return -2;
		p->op = LFU_OP_EQ;
		p->val = v;
		return 0;
	}

	case LFU_OPT_TYPE:
		if (lfu_parse_type(arg, &v) != 0)
			return lfu_bad("type", arg);
		p = lfu_pred_new(f, LFU_F_TYPE);
		if (p == NULL)
			return -2;
		p->op = LFU_OP_EQ;
		p->val = v;
		return 0;

	case LFU_OPT_PERM:
		if (lfu_parse_perm(arg, &op, &v) != 0)
			return lfu_bad("perm", arg);
		p = lfu_pred_new(f, LFU_F_PERM);
		if (p == NULL)
			return -2;
		p->op = (uint8_t)op;
		p->val = v;
		return 0;

	case LFU_OPT_ATTRS:
		if (lfu_parse_attrs(arg, &v, &v2) != 0)
			return lfu_bad("attrs", arg);
		p = lfu_pred_new(f, LFU_F_ATTRS);
		if (p == NULL)
			return -2;
		p->op = LFU_OP_ALL;
		p->val = v;
		p->val2 = v2;
		return 0;

	/* --- layout ------------------------------------------------------ */
	case LFU_OPT_OST:
		p = lfu_pred_new(f, LFU_F_OST);
		if (p == NULL)
			return -2;
		p->op = LFU_OP_LIST;
		if (lfu_parse_index_list(arg, p) != 0) {
			f->n--;
			return lfu_bad("index list", arg);
		}
		return 0;

	case LFU_OPT_POOL:
	case LFU_OPT_NAME: {
		enum lfu_field fld = opt == LFU_OPT_POOL ? LFU_F_POOL
							: LFU_F_NAME;

		p = lfu_pred_new(f, fld);
		if (p == NULL)
			return -2;
		p->op = LFU_OP_STR;
		if (strlen(arg) >= sizeof(p->str)) {
			f->n--;
			return lfu_bad("pattern", arg);
		}
		(void)snprintf(p->str, sizeof(p->str), "%s", arg);
		return 0;
	}

	case LFU_OPT_LAYOUT:
		if (lfu_parse_layout(arg, &v) != 0)
			return lfu_bad("layout", arg);
		p = lfu_pred_new(f, LFU_F_LAYOUT);
		if (p == NULL)
			return -2;
		p->op = LFU_OP_ANY;
		p->val = v;
		return 0;

	case LFU_OPT_MDT_HASH:
		if (lfu_parse_mdt_hash(arg, &v) != 0)
			return lfu_bad("mdt-hash", arg);
		p = lfu_pred_new(f, LFU_F_MDT_HASH);
		if (p == NULL)
			return -2;
		p->op = LFU_OP_EQ;
		p->val = v;
		return 0;

	default:
		return -1;	/* not ours */
	}
}

int lfu_filter_check(const struct lfu_filter *f)
{
	if (f->neg_pending) {
		fprintf(stderr, "lfu: `!` with no filter option after it\n");
		return -1;
	}
	return 0;
}

const char *lfu_field_name(enum lfu_field f)
{
	static const char *const names[LFU_F_MAX] = {
		"--atime", "--mtime", "--ctime", "--btime",
		"--uid", "--gid", "--type", "--perm", "--links",
		"--projid", "--attrs", "--dev-blocks",
		"--size", "--blocks",
		"--stripe-count", "--stripe-size", "--ost", "--pool",
		"--layout", "--mirror-count", "--comp-count",
		"--mdt-count", "--mdt-hash", "--name",
	};

	return f < LFU_F_MAX ? names[f] : "?";
}
