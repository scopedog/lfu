# HEAD — LU-20611 llapi: split cb_find_init's decider out

- **Commit:** `32090658f8b2` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **low**
- **Run:** opus, 4.5M tokens, $2.69, 5m25s

## Overall assessment

Mostly good. The cb_find_init()/find_decide() split checks out as behaviour-preserving; the remaining comments are about the commit message and one comment, fine to fold into the next refresh.

## Findings

### 1. `/COMMIT_MSG` (line 39)

(minor) This says two fixes are carried here, but the diff has a third: the new early return in printf_format_lustre() for an unknown letter or a trailing `%L`. The message doesn't mention it, and it changes behaviour on its own:

- for a file whose layout cannot be fetched (one off Lustre, say), `%Lx` used to be swallowed and print nothing; it is now printed as it stands, as it already was on Lustre.
- a trailing `%L` on such a file used to leave through the file branch's `layout == NULL` exit with rc still 2, so printf_format_string() did `fmt_char += 3` and read past the end of the format string. That exit predates this series.

Could the message list it, or could it go in a patch of its own?

### 2. `/COMMIT_MSG` (line 46)

(minor) If the unknown-letter check stays in this patch, it also fixes the file branch reading past the format string, which goes back to the original -printf code, so this would want:

    Fixes: 6b8e97b76c ("LU-10378 utils: add formatted printf to lfs find")

### 3. `lustre/utils/liblustreapi_pfind.c` (line 1794)

(style) This isn't a bug, but `path != NULL` is always true here in this patch: printf_format_string() is only reached from find_decide() with a walk's path, and %LF and the file branch above use `path` without testing it. The comment above only accounts for the other two tests. If the patch is refreshed, a few words on what the path test is for (keeping a pathless target scan's LMV from being taken for the stub?) would help someone reading this patch on its own.
