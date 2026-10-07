# bb7e771b7f — LU-20613 build: compile libscan_zfs.c as libzpool is built

- **Commit:** `bb7e771b7f5f` (bb7e771b7f, local review — not tied to a Gerrit change)
- **Review:** 1 finding(s), severity **low**
- **Run:** opus, 1.6M tokens, $1.24, 2m38s

## Overall assessment

Looks good. The flags match what OpenZFS 2.0 through 2.4 compile libzpool with, and the probe still passes against the 2.2.0 and 2.4.0 source trees with them added. The only nit is the commit message's version history, inline. There is no need to re-spin for it.

## Findings

### 1. `/COMMIT_MSG` (line 13)

(minor) If the patch is refreshed: the rename to LIBZPOOL_CPPFLAGS is openzfs commit b3b749161, first released in zfs-2.3.0. So the set is called LIBZPOOL_CPPFLAGS from 2.3 on, not only in 2.4. Two other statements also hold only from 2.3 on. First, zstream is built with the set only from 2.3 (92fca1c2d); every zfs-2.2.x tag still builds it without the set. Second, the Rules.am comment giving the reason ("ZFS_DEBUG can change shared data structures...") also only appears in 2.3. On ZFS 2.0 and 2.1, which Lustre still supports, the same flags come from AM_CPPFLAGS in lib/libzpool/Makefile.am instead. Perhaps: "2.0 and 2.1 set them in lib/libzpool/Makefile.am, 2.2 calls the set FORCEDEBUG_CPPFLAGS, and 2.3 renamed it LIBZPOOL_CPPFLAGS".
