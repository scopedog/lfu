# Maloo annotate list — sessions on CURRENT patchsets

Generated 2026-08-27. **Annotate, do not retest**: every class here is either
deterministic (a retest reproduces it) or already fixed locally.

Session URLs are `https://testing.whamcloud.com/test_sessions/<id>`.

## review-dne-selinux-ssk-part-2 / sanity-sec — 17 session(s)
**Ticket: LU-20598** — confirmed — 26/37 other owners, 23/23 on ours, same distro

- 68094 PS10 (enforced, 08-27 11:58) `946bd5c4-16f9-4db0-94a4-b70ace930721`
- 68095 PS10 (enforced, 08-27 12:11) `17d87c37-3746-4668-8617-49b57796c259`
- 68156 PS9 (enforced, 08-27 13:28) `3c9be73c-561a-4b74-8bdc-297ed1e8fbb6`
- 68157 PS9 (enforced, 08-27 13:27) `6cc7112e-1635-4524-87f1-0d50b8ce1456`
- 68158 PS9 (enforced, 08-27 13:41) `1d58c251-c32a-4ffe-986d-c709ba2229ff`
- 68159 PS9 (enforced, 08-27 13:32) `7b7b8808-e445-457e-bdd8-7cc09cae64ce`
- 68160 PS10 (enforced, 08-27 14:16) `949a930d-3d48-49e7-8461-712fbd041d06`
- 68163 PS8 (enforced, 08-27 14:42) `a6ec11ad-aae0-4f85-8b7c-265401b66fa2`
- 68288 PS3 (enforced, 08-27 14:49) `99d68030-b910-4815-976f-ce90cfe2cdca`
- 68340 PS1 (enforced, 08-26 21:11) `4fb7dce2-9808-4ac0-a33a-b20e9bf48e1d`
- 68413 PS1 (enforced, 08-27 10:37) `a06bddf9-e560-4ec4-b20e-144f9f2207f2`
- 68414 PS1 (enforced, 08-27 10:54) `c4022a6c-4f7d-4816-95b5-11978c83d806`
- 68415 PS1 (enforced, 08-27 15:39) `ec7b80ee-f58a-4b1f-a543-c15986d9f5df`
- 68416 PS1 (enforced, 08-27 15:50) `976a5fc3-845e-45d5-bc7a-c4f99f89de6a`
- 68417 PS1 (enforced, 08-27 15:32) `9314212f-bdce-4233-8093-2d3e84bb6789`
- 68418 PS1 (enforced, 08-27 16:21) `471a155b-fdc0-4c2f-bed3-4bf162a85f41`
- 68419 PS1 (enforced, 08-27 15:59) `bdb97812-058a-421f-a43c-fe2bf7c0623e`

## review-dne-zfs-part-5 / sanityn — 3 session(s)
**Ticket: LU-17857** — likely — "sanityn test_cleanup: Autotest time out"; matches the mode you read on 68340 (08-26). CONFIRM the subtest is test_cleanup when the session is open

- 68156 PS9 (enforced, 08-27 12:00) `6d2e84dd-8c6f-42dc-b910-5f4ba03da81b`
- 68157 PS9 (enforced, 08-27 14:35) `8948f2b6-4797-4a81-b45e-ca3f42ac03e5`
- 68417 PS1 (enforced, 08-27 13:29) `7bc4c110-0d0b-4fe1-932d-6287731b6c51`

## review-ldiskfs-arm / sanity — 3 session(s)
**Ticket: LU-20086** — strong — "sanity test_56ob aarch64: lfs find -mtime 2w wrong: found 0". Our 68417 session is test_56ob -mtime 3d, same test, same message, same arch

- 68340 PS1 (enforced, 08-26 23:06) `75f5b569-976b-47d1-82f0-f7df03948d5a`
- 68413 PS1 (enforced, 08-27 11:44) `05de31ce-c2da-4193-a1d4-6f6079dc6104`
- 68417 PS1 (enforced, 08-27 16:04) `43e9d3a1-b32d-4a5f-8d85-b5919bc119d8`

## review-dne-subtest-change / conf-sanity — 1 session(s)
**Ticket: NONE — ours, fixed** — 68288 test_166, the DNE placement bug. Fixed in round 11 and lab-proven; this clears on the next patchset

- 68288 PS3 (enforced, 08-27 10:19) `b6cb4274-65b1-4ab3-a2a5-14c15344e511`

## review-dne-part-4 / sanity-quota — 1 session(s)
**Ticket: ?** — subtest unknown; LU-20585 is a candidate if it is test_2

- 68288 PS3 (enforced, 08-27 16:05) `3fac0299-3a4c-46cd-bb05-ffa94e9b0c67`

## review-dne-zfs-part-2 / sanity-lfsck — 1 session(s)
**Ticket: ?** — 19/170 others. Subtest unknown — read it off the session

- 68157 PS9 (enforced, 08-27 16:02) `89392dda-b8d1-4c6b-9d06-debcf675678d`

## review-dne-zfs-part-3 / conf-sanity — 1 session(s)
**Ticket: NONE — do not annotate** — 68094: a 201-minute session TIMEOUT, no subtest failed. Not a test failure at all

- 68094 PS10 (enforced, 08-27 10:57) `9a9a32a0-8e38-4a22-bfc0-18304180303e`

## review-ldiskfs-ubuntu / sanity — 1 session(s)
**Ticket: LU-11210 or LU-15566** — our subtest is test_160h "expected 1 umount"; LU-11210 is "test_160h: expected 1 GC-thread", the same assertion shape. Pick whichever Maloo suggests

- 68094 PS10 (enforced, 08-27 15:25) `ff1fde4b-fc66-4543-97c4-82ad6a7d0315`

## review-dne-part-2 / sanity-lfsck — 1 session(s)
**Ticket: ?** — 20/170 others. Subtest unknown

- 68158 PS9 (enforced, 08-27 14:25) `ccf9515f-af77-4c09-898b-8db3148d02b5`

## review-dne-part-5 / sanityn — 1 session(s)
**Ticket: LU-17857** — same, confirm subtest

- 68340 PS1 (enforced, 08-26 20:29) `e2a02f11-c0f1-4768-8b19-6a2dae6e4c09`

## review-dne-zfs-part-4 / sanity-hsm — 1 session(s)
**Ticket: ?** — LU-20562 "sanity-hsm: cleanup failed" is a candidate

- 68340 PS1 (enforced, 08-26 23:25) `7db6bcf8-81b1-4c43-ad9e-468e0d5d1b19`

