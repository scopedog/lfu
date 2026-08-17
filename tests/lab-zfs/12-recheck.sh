#!/bin/bash
# Re-run only the four sanity tests that failed for a lab-environment reason,
# after chmod o+x $HOME.  They fail as "execvp fails ... (13): Permission
# denied" because the suites exec binaries out of the build tree, which lives
# in a 0700 home, so every test that drops to uid 500 dies before reaching any
# Lustre code.
#
#   bash 12-recheck.sh <label>
set -u
LABEL="${1:?usage: 12-recheck.sh <label>}"
chmod o+x "$HOME"
id -u 500 >/dev/null 2>&1 || { groupadd -g 500 runas; useradd -u 500 -g 500 -M -s /sbin/nologin runas; }
sudo -u \#500 test -x "$HOME/lustre-release/lustre/utils/lfs" && echo "uid 500 can exec lfs: yes" || echo "uid 500 can exec lfs: NO"

cd ~/lustre-release/lustre/tests || exit 1
export FSTYPE=zfs SLOW=no NAME=local MDSCOUNT=1 OSTCOUNT=2
mount | grep -q "on /mnt/lustre " || bash llmount.sh > /tmp/recheck-mount-$LABEL.log 2>&1

log=~/recheck-$LABEL.log
ONLY="27Ke 27W 102c 102j" bash sanity.sh > "$log" 2>&1
printf '%-10s pass=%-3s fail=%-3s  ' "$LABEL" "$(grep -c '^PASS ' $log)" "$(grep -cE '^(FAIL|ERROR) ' $log)"
grep -E "^(PASS|FAIL) (27Ke|27W|102c|102j) " "$log" | tr '\n' ' '; echo
