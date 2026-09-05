# Draft reply — 68094, the bulk-records thread (NOT POSTED)

Change:   68094 (LU-20603 llapi: namespace scanner API), current PS17
File:     Documentation/man3/llapi_scan_namespace.3, line 22
Thread:   adilger 91d84157_96ce6938 ("Returning a single record for each
          call is OK for POSIX namespace scanning..."), left on PS16
Reply to: f68581e4_a4a33b21  <- my own last reply in that thread, on PS16
          (reply against the revision the comment was left on: PS16)
Post with: ssh -p 29418 hnishida@review.whamcloud.com gerrit review 68094,16 --json
           {"tag":"review-reply","notify":"OWNER","comments":{
             "Documentation/man3/llapi_scan_namespace.3":[
               {"line":22,"in_reply_to":"f68581e4_a4a33b21",
                "unresolved":true,"message":"..."}]}}

Code it describes: 4c61e1621a on statx-port-fixed, UNPUSHED.
Numbers: bench-data/2026-09-05/README.md

---

Built it. `llapi_scan_namespace_open()` / `llapi_scan_next()` /
`llapi_scan_close()`: an iterator over the same scan, so the caller pulls N
records per call on its own thread while the scan fills the other of two
batches and blocks when it is full -- what is in flight is bounded by the
batch size, not by the tree.

Each record is copied into the batch with everything it points at (path,
name, layout, LMV, linkea, jobid), because a callback record points into
buffers the scan reuses for the next object. The descriptors are not
carried and read -1.

Measured on a real mount (ldiskfs, MDSCOUNT=2, 20,021 objects, medians of
15 alternating runs):

{noformat}
threads batch     callback      batch     delta
      1  1024     2744.1 ms  2755.4 ms    +0.4%
      4  1024      938.2 ms   951.8 ms    +1.4%
      4     1      947.5 ms  1114.4 ms   +17.6%
{noformat}

On a tree whose records carry layouts (1002 of them, and an LMV) it is
inside the noise: +0.5% at four threads, -0.8% at one. Off Lustre, where
per-object work is a cached lstat() and the copy is the largest share it
will ever be, the same batch costs +5-8% -- that is the upper bound, not
the figure.

So my earlier "filling a buffer with N records costs more than the N
callbacks it removes" was too strong. The copy is real, but next to an MDT
ioctl it is under 1.5%. What does cost is a batch of 1, at +17.6%: the
lock round trip per record, removing nothing.

Verified against the callback scan field for field -- path, name, FID,
both masks, size, mode, lmmsize, lmvsize, stripe count -- identical at
every batch size and thread count, on both trees. sanity 56El, 157c and
160aa-ad pass.

Not pushed yet, because it is a new entry point rather than a change to
this one: it can go as a change of its own on top of the series, or be
squashed into this one if you would rather review it alongside the API.
Which do you prefer?

---

Open before posting:
1. The retraction paragraph ("my earlier ... was too strong") is
   deliberate -- cut it if you would rather not.
2. The closing question hands placement to him. My recommendation if you
   would rather decide: a change of its own on top of 68420, since 68094
   is at PS17 with fifteen of his comments still open.
3. Nothing is pushed, so the reply describes code he cannot fetch. Either
   push first, or keep the "not pushed yet" sentence.
