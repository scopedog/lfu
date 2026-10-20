# LU-20730: draft Jira comment on the nodemap role (item 2), NOT POSTED

Andreas asked (LU-20730, 2026-09-10) whether "byfid" RBAC is enough for a
scan or it needs its own role, and asked Sebastien. Draft for the user,
Jira wiki markup (whamcloud Jira Server 9.12):

----
[~sebastien], following Andreas' comment above: the remote scan now checks
{{CAP_DAC_READ_SEARCH}} on the client, and the MDT filters by nodemap:

* a nodemap with a UID/GID/PROJID offset gets only the objects with one of
  those IDs in its ranges, mapped back to its own IDs;
* an admin, trusted nodemap without an offset gets everything;
* any other nodemap gets {{-EPERM}}.

That last rule is a stand-in for the role Andreas suggested.  We would
rather add {{NODEMAP_RBAC_SCAN_OPS}} ("scan_ops") than reuse {{byfid_ops}}:
byfid lets a client open a file it already knows the FID of, a scan hands
out every FID at once, and a site may want the first without the second.
With the role, the rules become:

* role absent: {{-EPERM}}, whatever else the nodemap says;
* role present and an offset set: filtered as above;
* role present and no offset: everything.

Like the other roles it would be on by default, so nothing changes for a
site that does not use RBAC.  Does that match what you had in mind?
----

Code impact if agreed: one enum value + name in lustre_nodemap.h, the
check in tgt_lfu_scan_policy() (tgt_handler.c), lctl/man for the role
name, sanity-sec coverage.  NOT started; waits for Sebastien.
