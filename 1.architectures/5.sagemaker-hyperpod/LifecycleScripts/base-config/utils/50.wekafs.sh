#!/bin/bash
#
# This script is to be used to perform the initial setup of the Weka containers on a new EC2 P5 instance.
# It will create the containers and attach the ENIs to the instances.
# It will also create the Weka resources and apply them to the containers.
# The script should be executed on each EC2 instance.
#
# NOTE: Reinstallation will automatically remove the old containers and create new ones.

# Make this equal to 1 to enable debug prints
debug=1

declare -A wekaclusters
wekaclusters["dev"]="dev"

# Set the script to exit if any command fails
set -e

# Instance specifications - List of resources per instance type
# ---P4DE.X24LARGE---
declare -A INST_RESOURCES=( ["DRIVES"]="1" ["DRIVE_CORE_IDS"]="47" ["DRIVE1_CORE_IDS"]="46" ["COMPUTE"]="2" ["COMPUTE_CORE_IDS"]="45,44" ["COMPUTE1_CORE_IDS"]="43,42" ["FE"]="1" ["FE_CORE_IDS"]="41" ["NVMES"]="/dev/nvme1n1 /dev/nvme3n1" ["NVMES1"]="/dev/nvme5n1 /dev/nvme7n1")

function installweka {
    # Install WEKA
    upgrade=$1
    if [ "$upgrade" == "upgrade" ]; then
        echo "Upgrading WekaFS"
        cd /tmp
        cp /fsx/admin/scripts/weka-4.2.5.tar .
        tar xf  weka-4.2.5.tar
        cd weka-4.2.5 && sudo WEKA_CGROUPS_MODE=none ./install.sh
    fi

    #-----------------------#
    #  Containers creation, only required for WEKA internal testing, Stability will run locally on each server  #
    #-----------------------#
    # Get the instance mgmt IP from the hostname command
    mgmt_ip=$(hostname -I | awk '{print $1}')

    # Remove existing containers and create new ones
    sudo weka local stop && sudo weka local rm --all --force || echo "Exit: container removal failed"
    sudo weka local setup container -n drives0 --management-ips $mgmt_ip --base-port 14000 || echo "Exit: DRIVES container creation failed"
    sudo weka local setup container -n drives1 --management-ips $mgmt_ip --base-port 14200 || echo "Exit: DRIVES container creation failed"
    sudo weka local setup container -n compute0 --management-ips $mgmt_ip --base-port 14400 || echo "Exit: COMPUTE container creation failed"
    sudo weka local setup container -n compute1 --management-ips $mgmt_ip --base-port 14500 || echo "Exit: COMPUTE container creation failed"
    sudo weka local setup container -n frontend0 --management-ips $mgmt_ip --base-port 14600 || echo "Exit: FRONTEND container creation failed"
}

function main {
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')] 50.wekafs.sh: START" >&2

    if [ "$1" == "SlurmNodeType.COMPUTE_NODE" ]; then
        # Call installweka function to install WEKA software
        installweka

        # attach CPU Core IDs to drives0 container
        sudo weka local resources -C drives0 cores ${INST_RESOURCES["DRIVES"]} --core-ids ${INST_RESOURCES["DRIVE_CORE_IDS"]} --only-drives-cores 
        # Set drives0 container's failure domain to the instance's IP with dots replaced with dashes
        sudo weka local resources -C drives0 failure-domain --name $(hostname -I | awk '{gsub( "[:'\.']","-" ); print $1"-0"}')
        # Apply all configuration changes to the drives0 container. Conatiner will come up in the STEM mode and will be ready to join a cluster
        sudo weka local resources apply -C drives0 -f &

        # attach CPU Core IDs to drives1 container
        sudo weka local resources -C drives1 cores ${INST_RESOURCES["DRIVES"]} --core-ids ${INST_RESOURCES["DRIVE1_CORE_IDS"]} --only-drives-cores 
        # Set drives0 container's failure domain to the instance's IP with dots replaced with dashes
        sudo weka local resources -C drives1 failure-domain --name $(hostname -I | awk '{gsub( "[:'\.']","-" ); print $1"-1"}')
        # Apply all configuration changes to the drives0 container. Conatiner will come up in the STEM mode and will be ready to join a cluster
        sudo weka local resources apply -C drives1 -f &

        # attach CPU Core IDs to compute0 conatiner
        sudo weka local resources -C compute0 cores ${INST_RESOURCES["COMPUTE"]} --core-ids ${INST_RESOURCES["COMPUTE_CORE_IDS"]} --only-compute-cores 
        # Set compute0 container's memory to 4GiB times the number of cores
        sudo weka local resources -C compute0 memory $((${INST_RESOURCES["COMPUTE"]}*4))GiB
        # Set compute0 container's failure domain to the instance's IP with dots replaced with dashes
        sudo weka local resources -C compute0 failure-domain --name $(hostname -I | awk '{gsub( "[:'\.']","-" ); print $1"-0"}')
        # Apply all configuration changes to the compute0 container. Conatiner will come up in the STEM mode and will be ready to join a cluster
        sudo weka local resources apply -C compute0 -f &

        # attach CPU Core IDs to compute0 conatiner
        sudo weka local resources -C compute1 cores ${INST_RESOURCES["COMPUTE"]} --core-ids ${INST_RESOURCES["COMPUTE1_CORE_IDS"]} --only-compute-cores 
        # Set compute0 container's memory to 4GiB times the number of cores
        sudo weka local resources -C compute1 memory $((${INST_RESOURCES["COMPUTE"]}*4))GiB
        # Set compute0 container's failure domain to the instance's IP with dots replaced with dashes
        sudo weka local resources -C compute1 failure-domain --name $(hostname -I | awk '{gsub( "[:'\.']","-" ); print $1"-1"}')
        # Apply all configuration changes to the compute0 container. Conatiner will come up in the STEM mode and will be ready to join a cluster
        sudo weka local resources apply -C compute1 -f &

        # attach CPU Core IDs to frontend0 conatiner
        sudo weka local resources -C frontend0 cores ${INST_RESOURCES["FE"]} --core-ids ${INST_RESOURCES["FE_CORE_IDS"]} --only-frontend-cores 
        # Apply all configuration changes to the frontend0 container. Conatiner will come up in the STEM mode and will be ready to join a cluster
        sudo weka local resources apply -C frontend0 -f
    fi

    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')] 50.wekafs.sh: STOP" >&2
}

main "$@"
