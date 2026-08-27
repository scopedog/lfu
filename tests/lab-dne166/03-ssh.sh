#!/bin/bash
# Stage 3: root-to-root ssh from the runner (client) to the server.
# test-framework's do_facet/do_node reach the MDS this way, and the fixed
# test_166 additionally zconf_mount()s a client on the MDS over the same path.
set -e
SRV=${SRV:-lfu-dne-srv}
sudo install -d -m 700 /root/.ssh
sudo test -f /root/.ssh/id_ed25519 ||
	sudo ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519
sudo cat /root/.ssh/id_ed25519.pub
