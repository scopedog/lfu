/* kernel-mode test stub for lib/glob.c's glob_match(): same '*' '?' '[...]'
 * semantics as fnmatch() with no flags, so back it with that here. */
#include <stdbool.h>
#include <fnmatch.h>
static inline bool glob_match(char const *pat, char const *str)
{
	return fnmatch(pat, str, 0) == 0;
}
