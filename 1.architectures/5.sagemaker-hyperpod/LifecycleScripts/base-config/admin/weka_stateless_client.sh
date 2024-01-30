#!/bin/bash
##############################################################################################################
# This script is used to install Weka Agent and mount the wekafs filesystem using a stateless client approach #
##############################################################################################################

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables
# Input file for IP addresses is expected to be passes as the first argument to the script.
/opt/slurm/bin/scontrol show hostnames $(sinfo -h -o "%N" -p dev) | sort -u > /tmp/ip_list
IP_LIST=/tmp/ip_list

#############################################################################################################
# Print error message
# Arguments:
#   $1 - error message
# Outputs:
#   Writes error message to stderr
#############################################################################################################
function error() {
        printf "[ $(date +%Y-%M-%dT%H:%M:%S) ] ERROR: %s\n" "$@"
}

#############################################################################################################
# Print message
# Arguments:
#   $1 - message
# Outputs:
#   Writes message to stdout
#############################################################################################################
function message() {
        printf "[ $(date +%Y-%M-%dT%H:%M:%S) ] %s\n" "$@"
}

get_weka_cluster_ip() {
    IPLIST=$1
    while IFS= read -r hostname; do
        # Use 'nc' to check if the IP is reachable on TCP port 14000
        if nc -zvw3 "$hostname" 14000; then
            echo "$hostname"
            return
        fi
    done < "$IPLIST"
    error "Unable to find a reachable IP address for the Weka cluster on port 14000"
    return 1
}

main() {
    mkdir -p /weka

    mount_endpoint=$(get_weka_cluster_ip $IP_LIST)

    if [ -z "$mount_endpoint" ] ]; then
        error "Unable to find a reachable IP addresses for the Weka clusters on port 14000"
        exit 1
    fi
    message "Installing Weka Agent from $mount_endpoint"
    # Install Weka Agent
    curl -sSL "http://$mount_endpoint:14000/dist/v1/install" | sudo -E WEKA_CGROUPS_MODE=none bash

    sudo sed -i '/weka/d' /etc/fstab
    echo "${mount_endpoint}/Default /weka wekafs x-systemd.requires=weka-agent.service,x-systemd.mount-timeout=infinity,_netdev,net=udp 0 0" | tee -a /etc/fstab
    
    systemctl daemon-reload
    mount -a
    sudo chmod 1777 /weka
}

main "$@"
