#!/bin/bash
# Two c3-standard-8 instances, srv + cli, in the first zone with capacity.
for z in us-central1-a us-central1-b us-central1-c us-central1-f us-east1-b us-east1-c us-east1-d; do
	if gcloud compute instances create lfu-split-srv lfu-split-cli --zone=$z \
		--machine-type=c3-standard-8 --image-family=rocky-linux-9 \
		--image-project=rocky-linux-cloud --boot-disk-size=120GB \
		--boot-disk-type=pd-balanced --no-service-account --no-scopes; then
		echo "ZONE=$z"; exit 0
	fi
	gcloud compute instances delete lfu-split-srv lfu-split-cli --zone=$z --quiet 2>/dev/null
done
exit 1
