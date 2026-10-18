# 69729 PS2 -- adilger 10-17, replies for the next PS (held, not posted)

**POSTED by the user 10-17 evening** on PS2. The trim (54da857f6c) is still LOCAL: the "Done." needs PS3 to be true.

Local: igif-1017 54da857f6c (man paragraph trimmed); PS2 = a1017-69729-ps2.

## 5ad694d4 (change level) "Why not just read the ROOT/ inode directly by name at startup?"

Reading ROOT by name needs a new entry point in the ldiskfs scan plugin, and the plugin ships separately from liblustreapi, so the library must also handle an older plugin without it. This change needs no plugin change: the .lustre linkea is already in the map the pre-pass builds. If .lustre has no linkea, the root stays LU_ROOT_FID, as before. For a case only pre-2.4 ldiskfs can hit, the smaller change seemed better.

## 2320b213 Documentation/man3/llapi_find_device.3:276 (man page too long)

Done.
