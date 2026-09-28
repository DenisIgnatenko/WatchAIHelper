#!/usr/bin/env bash
# One-time preparation of a fresh Ubuntu Lightsail instance. Idempotent: safe to run again.
# Run from the Mac:
#  ssh -i ~/.ssh/aicopilot-lightsail.pem ubuntu@<STATIC_IP> 'bash -s' < deploy/setup-server.sh
set -euo pipefail

echo "== Docker"
if ! command -v docker >/dev/null; then
 # Official Docker packages (engine + compose plugin).
 curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker ubuntu

echo "== Swap (2 GB): headroom for JVM + PostgreSQL on a 2 GB instance"
if [ ! -f /swapfile ]; then
 sudo fallocate -l 2G /swapfile
 sudo chmod 600 /swapfile
 sudo mkswap /swapfile
 sudo swapon /swapfile
 echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

echo "== Automatic security updates"
sudo apt-get install -y unattended-upgrades >/dev/null
sudo dpkg-reconfigure -f noninteractive unattended-upgrades

echo "== Application directory"
sudo mkdir -p /opt/aicopilot
sudo chown ubuntu:ubuntu /opt/aicopilot
chmod 700 /opt/aicopilot

echo "Done. Docker: $(docker --version)"
