#!/bin/bash
# 10-09 lab, stage 11 (as root): after stage 9, the gate re-run and 68415.
while ! grep -q "NINE DONE" /tmp/lab1009-gate.out; do sleep 20; done
GATE_RUN=2 bash /tmp/08-gate.sh fix gate
while ! grep -q "BUILD-OK\|failed" /tmp/lab1009-build-follow.out; do sleep 20; done
bash /tmp/10-follow.sh old follow
echo ELEVEN DONE >> /tmp/lab1009-follow.out
