#!/bin/bash
# Run LOCALLY.  Cuts the series the lab builds and copies it to the lab node.
# HEAD is 68420: 68419 has the --since-cookie code and 68420 has 160aa/ab/ac,
# and the lab is useless without both.
#
#   TARGET=nishida@192.168.122.10 ./00-patches.sh      # a libvirt clone VM
#   TARGET=gcp:lfu-160ac ./00-patches.sh               # a GCP instance
set -e
W=${W:-$HOME/projects/lustre/lustre-lu20603}
BASE=${BASE:-5afbab284e}
HEADC=${HEADC:-191c17a792}          # 68420 PS2
TARGET=${TARGET:?set TARGET=user@host or gcp:<instance>}
ZONE=${ZONE:-us-east1-b}

cd "$W"
git merge-base --is-ancestor "$BASE" "$HEADC" ||
	{ echo "$BASE is not an ancestor of $HEADC"; exit 1; }
rm -rf /tmp/lfu-patches && mkdir -p /tmp/lfu-patches
git format-patch -o /tmp/lfu-patches "$BASE".."$HEADC" >/dev/null
echo "cut $(ls /tmp/lfu-patches/*.patch | wc -l) patches $BASE..$HEADC"

# the two the lab exists to exercise must be in there
grep -lq "since-cookie" /tmp/lfu-patches/*.patch ||
	{ echo "no --since-cookie patch in the set"; exit 1; }
grep -lq "test_160ac" /tmp/lfu-patches/*.patch ||
	{ echo "no 160ac patch in the set -- the lab would prove nothing"; exit 1; }

case "$TARGET" in
gcp:*)
	I=${TARGET#gcp:}
	gcloud compute ssh "$I" --zone "$ZONE" --command "rm -rf ~/patches && mkdir -p ~/patches"
	gcloud compute scp /tmp/lfu-patches/*.patch "$I":~/patches/ --zone "$ZONE" ;;
*)
	ssh -o StrictHostKeyChecking=no "$TARGET" "rm -rf ~/patches && mkdir -p ~/patches"
	scp -q -o StrictHostKeyChecking=no /tmp/lfu-patches/*.patch "$TARGET":patches/ ;;
esac
echo "PATCHES ON $TARGET"
