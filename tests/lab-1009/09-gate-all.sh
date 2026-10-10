#!/bin/bash
# 10-09 lab, stage 9 (as root): the gate check, then the race on the gate arm.
bash /tmp/08-gate.sh old fix gate
ARMS=gate PAD=99000 bash /tmp/06-once-all.sh
echo NINE DONE >> /tmp/lab1009-gate.out
