#!/bin/bash
set -x
set -e

moveDockertoScratch() {
    target="/scratch/docker"
    sudo systemctl stop docker.dcgmi
    #sudo docker stop $(sudo docker ps -a -q)
    sudo systemctl stop docker
    sudo systemctl stop docker.socket
    sudo systemctl stop containerd
    sudo mkdir -p $target
    sleep 30
    sudo mv /var/lib/docker $target

    #todo improve this for future proper json parsing
    cat > /etc/docker/daemon.json << EOF
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    },
    "data-root": "$target",
    "bip":"192.168.0.1/24"
}
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo systemctl start docker.dcgmi
}

# main
# ----------------------------------------------------------------------------
main() {
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')] 40.move.docker.scratch.sh: START" >&2
    if [ "$1" == "SlurmNodeType.COMPUTE_NODE" ]; then
        moveDockertoScratch
    fi
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')] 40.move.docker.scratch.sh: STOP" >&2
}

main "$@"
