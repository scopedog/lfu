#!/bin/bash
# Run LOCALLY, not on the instance.  Cuts the series the lab builds and copies
# it up.  HEAD is 68420: 68419 has the --since-cookie code and 68420 has
# 160aa/ab/ac, and the lab is useless without both.
set -e
W=${W:-$HOME/projects/lustre/lustre-lu20603}
BASE=${BASE:-5afbab284e}
HEADC=${HEADC:-191c17a792}          # 68420 PS2
INST=${INST:?set INST=<gcp instance name>}
ZONE=${ZONE:-us-east1-b}

cd "$W"
git merge-base --is-ancestor "$BASE" "$HEADC" ||
	{ echo "$BASE is not an ancestor of $HEADC"; exit 1; }
rm -rf /tmp/lfu-patches && mkdir -p /tmp/lfu-patches
git format-patch -o /tmp/lfu-patches "$BASE".."$HEADC" >/dev/null
n=$(ls /tmp/lfu-patches/*.patch | wc -l)
echo "cut $n patches $BASE..$HEADC"
ls /tmp/lfu-patches | sed 's/^/  /'

# the two the lab exists to exercise must be in there
grep -lq "since-cookie" /tmp/lfu-patches/*.patch ||
	{ echo "no --since-cookie patch in the set"; exit 1; }
grep -lq "test_160ac" /tmp/lfu-patches/*.patch ||
	{ echo "no 160ac patch in the set -- the lab would prove nothing"; exit 1; }

gcloud compute ssh "$INST" --zone "$ZONE" --command "rm -rf ~/patches && mkdir -p ~/patches"
gcloud compute scp /tmp/lfu-patches/*.patch "$INST":~/patches/ --zone "$ZONE"
echo "PATCHES ON $INST"
