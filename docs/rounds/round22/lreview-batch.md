# HEAD — LU-20603 llapi: pull a scan's records in batches

- **Commit:** `4c61e1621a2b` (HEAD, local review — not tied to a Gerrit change)
- **Review:** 3 finding(s), severity **medium**
- **Run:** opus, 4.6M tokens, $4.68, 9m32s

## Overall assessment

Mostly good, a few comments inline. The one point worth settling before this lands is the threading contract of struct llapi_scan_handle: the implementation assumes exactly one thread ever touches a handle, and neither the header nor llapi_scan_next(3) says so, which is easy to get wrong given llapi_scan_namespace(3) documents its own callback as concurrent.

## Findings

### 1. `lustre/utils/liblustreapi_scan_batch.c` (line 427)

Is a handle meant to be used by exactly one thread? Nothing in the header, the kerneldoc or llapi_scan_next(3) says so, and llapi_scan_namespace(3) is explicit that its callback is called concurrently, so a reader may well assume the same freedom here.

Two consumers calling llapi_scan_next() on one handle corrupts the heap. The reset of sh_out happens before the wait, so the second waiter never resets the batch it installs as sh_fill:

    C1: reset(B1); wait; swap -> sh_fill=B1, sh_out=B0
    C2: (still in wait) wakes on the next full batch
        swap -> sh_fill=B0, whose sb_count is still sb_cap
    producer: scan_batch_append(B0) writes sb_recs[sb_cap]

End of scan is a hang for the same reason: scan_batch_thread() signals sh_ready once, so a second waiter is never woken.

A cancel from a second thread also looks unsafe: while the consumer sits in pthread_cond_wait(&sh_ready), llapi_scan_close() joins the scan thread and then scan_handle_free()s the handle and destroys sh_lock underneath it.

Documenting "one consumer thread per handle, and close it from that thread" in the header and the man page would be enough; enforcing it would be better.

### 2. `lustre/utils/liblustreapi_scan_batch.c` (line 54)

This isn't a bug, but the claim doesn't quite match scan_batch_reset(), which keeps only the single largest chunk and frees the rest. A batch whose payloads exceed SCAN_ARENA_CHUNK therefore mallocs and frees the extra chunks on every batch, not just the first.

With the 1024-record default that is reachable: a deepish path plus an 8-stripe lmm is a few hundred bytes per record, so 1024 of them can pass 256 KiB. Resetting ac_used on the whole list instead of freeing all but one would make the comment true.

### 3. `lustre/utils/liblustreapi_scan_batch.c` (line 224)

This isn't a bug, but the (const void **) casts on sr_lmm, sr_lmv, sr_src_name and sr_jobid are punning a typed pointer-to-pointer, which liblustreapi builds without -fno-strict-aliasing. Having scan_batch_copy_bytes() take the source and return the arena copy would let all four sites stay typed; only sr_linkea is genuinely a const void * today.
