/* printf_format_want() lifted verbatim from liblustreapi_pfind.c */
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <lustre/lustreapi.h>

static __u64 printf_format_want(const char *fmt, bool *needs_path)
{
	const char *c = fmt;
	__u64 want = 0;

	if (needs_path != NULL)
		*needs_path = false;

	while (*c != '\0') {
		if (*c++ != '%')
			continue;

		/* GNU find accepts "%----10s": the flags, then a width */
		while (*c == '-')
			c++;
		while (*c >= '0' && *c <= '9')
			c++;

		switch (*c) {
		case '\0':
			return want;
		case 'p':	/* the path as walked */
			if (needs_path != NULL)
				*needs_path = true;
			break;
		case 's':
			want |= LLAPI_SCAN_SIZE | LLAPI_SCAN_LAZY_SIZE;
			break;
		case 'b':
		case 'k':
			want |= LLAPI_SCAN_BLOCKS | LLAPI_SCAN_LAZY_BLOCKS;
			break;
		case 'L':
			/*
			 * Whether a %L directive is answered from the layout
			 * or from the directory stripe is the object's own
			 * mode, so a format carrying one asks for both.
			 */
			if (c[1] != '\0' && strchr("chiopS", c[1]) != NULL)
				want |= LLAPI_SCAN_LAYOUT | LLAPI_SCAN_LMV;
			break;
		}

		/*
		 * One character consumed whatever it was: %% leaves the
		 * second per cent a literal, and the second character of a
		 * two-character directive is not a directive itself.
		 */
		c++;
	}

	return want;
}

struct t { const char *fmt; bool path; __u64 want; };

int main(void)
{
	const __u64 LAY = LLAPI_SCAN_LAYOUT | LLAPI_SCAN_LMV;
	const __u64 SZ = LLAPI_SCAN_SIZE | LLAPI_SCAN_LAZY_SIZE;
	const __u64 BL = LLAPI_SCAN_BLOCKS | LLAPI_SCAN_LAZY_BLOCKS;
	struct t tests[] = {
		{ "", false, 0 },
		{ "no directives at all\n", false, 0 },
		{ "%p\n", true, 0 },
		{ "%i %p\n", true, 0 },
		{ "%-10p", true, 0 },
		{ "%----10p", true, 0 },
		{ "%010p", true, 0 },
		{ "%%p", false, 0 },		/* a literal per cent, then p */
		{ "%%%p", true, 0 },		/* literal, then the real one */
		{ "%Lp", false, LAY },		/* pool name, not the path */
		{ "%-8Lp", false, LAY },
		{ "%LF", false, 0 },
		{ "%LP", false, 0 },
		{ "%La %LA", false, 0 },
		{ "%Lc", false, LAY },
		{ "%Lh", false, LAY },
		{ "%Li", false, LAY },
		{ "%Lo", false, LAY },
		{ "%LS", false, LAY },
		{ "%s", false, SZ },
		{ "%b", false, BL },
		{ "%k", false, BL },
		{ "%s %b %Lc", false, SZ | BL | LAY },
		{ "%i %n %u %g %m %M %y", false, 0 },
		{ "%a %A@ %c %C@ %t %T@ %w %W@", false, 0 },
		{ "%", false, 0 },		/* per cent at the end */
		{ "%-", false, 0 },
		{ "%10", false, 0 },
		{ "trailing text %i then %Lc end", false, LAY },
		{ "%L", false, 0 },		/* %L with nothing after it */
	};
	int fails = 0;
	unsigned i;

	for (i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
		bool path = true;
		__u64 want = printf_format_want(tests[i].fmt, &path);

		if (path != tests[i].path || want != tests[i].want) {
			printf("FAIL \"%s\": path=%d want=%#llx (expected path=%d want=%#llx)\n",
			       tests[i].fmt, path, (unsigned long long)want,
			       tests[i].path, (unsigned long long)tests[i].want);
			fails++;
		}
	}
	/* NULL needs_path is allowed: find_device_want() passes it */
	(void)printf_format_want("%p%Lc", NULL);

	printf("%u cases, %d failures\n",
	       (unsigned)(sizeof(tests) / sizeof(tests[0])), fails);
	return fails != 0;
}
