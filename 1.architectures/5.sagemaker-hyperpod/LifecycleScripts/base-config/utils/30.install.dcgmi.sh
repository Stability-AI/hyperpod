#!/bin/bash

# First the HyperPod docker installation is crap, we attempt to fix this
# This script installs dcgmi as a docker container to monitor GPU utilisation with any openmetrics scraping tool such as Prometheus or Datadog Agent

set -x
set -e

fixDocker() {
    apt-get remove -y --purge docker*
    apt-get update
    apt-get install -y containerd docker.io
}

setupDCGMI() {
    cat > /etc/systemd/system/docker.dcgmi.service <<EOF
[Unit]
Description=dcgmi service
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker exec %n stop
ExecStartPre=-/usr/bin/docker rm %n
ExecStartPre=/usr/bin/docker pull nvcr.io/nvidia/k8s/dcgm-exporter:3.1.3-3.1.2-ubuntu20.04
ExecStart=/usr/bin/docker run --rm --name %n --gpus all -p 9400:9400 nvcr.io/nvidia/k8s/dcgm-exporter:3.1.3-3.1.2-ubuntu20.04
ExecStop=/usr/bin/docker exec %n stop

[Install]
WantedBy=default.target
EOF
    systemctl enable docker.dcgmi
    systemctl start docker.dcgmi
}

# main
# ----------------------------------------------------------------------------
main() {
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')] 30.install_dcgmi.sh: START" >&2
    if [ "$1" == "SlurmNodeType.COMPUTE_NODE" ]; then
        fixDocker
        setupDCGMI
    fi
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')] 30.install_dcgmi.sh: STOP" >&2
}

main "$@"
