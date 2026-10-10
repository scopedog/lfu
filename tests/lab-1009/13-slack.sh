#!/bin/bash
# 10-09 lab, stage 13 (as root): the clock slack (68417 lreview #3).
while ! grep -q "BUILD-OK\|failed" /tmp/lab1009-build-slack.out; do sleep 20; done
GATE_RUN=3 GATE_WAIT=620 bash /tmp/08-gate.sh fix slack
bash /tmp/04-sanity.sh slack ldiskfs
bash /tmp/04-sanity.sh slack zfs
echo THIRTEEN DONE > /tmp/lab1009-thirteen.done
