# libzpool leaks a pthread key per kernel_init()/kernel_fini()

`tsdleak.c` cycles `kernel_init(SPA_MODE_READ)`/`kernel_fini()` N times,
optionally deleting `rrw_tsd_key` after each, then counts the pthread keys
still free. Needs only the libzpool runtime (no pool, no root):

    gcc -o tsdleak tsdleak.c -lzpool -lnvpair -lpthread
    ./tsdleak 0 10     # unfixed: 1014 keys free
    ./tsdleak 1 1100   # with pthread_key_delete: 1024 free

Measured 2026-10-05 on Ubuntu libzpool 2.2.2. OpenZFS 2.2.0 and master:
`tsd_create()` is a bare `pthread_key_create()`, `tsd_destroy()` is empty,
and `kernel_fini()` never deletes the key. Fixed in our 68163
(`scan_zfs_fini()`), found by the Gerrit AI review of PS27.
