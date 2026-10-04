#!/bin/bash
# Client: mount the server's filesystem.  $1 = server IP.
set -e
sudo modprobe lustre
sudo mkdir -p /mnt/testfs
sudo mount -t lustre "$1@tcp:/testfs" /mnt/testfs
sudo lctl get_param -n version
df -t lustre -h
echo "STAGE3C OK"
