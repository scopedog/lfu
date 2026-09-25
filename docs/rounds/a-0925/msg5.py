# 09-25c: one paragraph for 68163's message: osd-zfs xattr storage objects.
import subprocess, sys
msg = subprocess.check_output(['git', 'log', '-1', '--format=%B']).decode()
anchor = "date on osd-zfs.\n"
add = """
osd-zfs keeps an xattr that does not fit in the SA in a directory of
its own, one object for each value. These objects hold the xattrs of
another object, like an ldiskfs ea_inode, so they are neither reported
nor counted. They have no ZPL_MODE, so otherwise they would be counted
in ss_skipped, and lfs find --device would report damage that is not
there.
"""
assert msg.count(anchor) == 1 and 'ea_inode' not in msg
msg = msg.replace(anchor, anchor + add, 1)
subprocess.run(['git', 'commit', '-q', '--amend', '-F', '-'], input=msg.encode(), check=True)
