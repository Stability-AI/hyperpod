# Save this file as weka_init.sh set as executable and run.
# Input file for IP addresses is expected to be passes as the first argument to the script.
#!/bin/bash

# Make this equal to 1 to enable debug prints
debug=1
wekaversion="4.2.5"
# File the server IPs, one IP per line
/opt/slurm/bin/scontrol show hostnames $(sinfo -h -o "%N" -p dev) | sort -u > /tmp/ip_list
IP_LIST=/tmp/ip_list
wekaclustername="dev"
readonly NUM_SERVERS=$(wc -l < ${IP_LIST})
readonly NUM_NODES=${NUM_SERVERS}*2

assert() {
	local msg=$1
	echo $msg
	exit 1
}

# This function waits for system reach certain state
conditionWait() {
        local wekacmd="$1"
        local control="$2"
        local msg="$3"
        local readonly __RETRY_WAIT=${6:-6} # Unless the wait is explicitly passed, will wait only 6 sec before next retry
        local __RETRIES=${6:-6} # Unless number of tries is explicitly passed, run the command only 6 times.

        echo $msg
        while [ $__RETRIES -gt 0 ]; do
                r_rdy=$(eval "${wekacmd}")
                [[ $debug ]] &&  echo $r_rdy
                [[ $debug ]] && printf "\n[ debug ] Retries left - %s" $__RETRIES
                if [[ $r_rdy -eq $control ]]; then
                        return 0 # Success, return to main
                else
                        : $((__RETRIES--)) # Decrement number of retries left
                        sleep $__RETRY_WAIT
                fi
        done
	# Reached max number if retries, bail out
	echo "Exit: Reached max number of retries"
	return 1
}

#-----------------------#
#   Cluster creation    #
#-----------------------#

weka cluster create $(cat $IP_LIST) $(sed 's/$/:14200/' $IP_LIST) |& tee -a /tmp/log || assert "Exit: weka cluster create failed"
conditionWait "weka cluster container -F status=UP --no-header 2>/dev/null|wc -l" ${NUM_NODES} "Waiting for the DRIVE containers to come up.."
#sleep 120

#----------#
# DRIVES   #
#----------#

# Add drives to the DRIVES containers
weka cluster container --no-header -F container=drives0 -o id | xargs -I {} -P${NUM_SERVERS} weka cluster drive add {} /dev/nvme1n1 /dev/nvme3n1 || assert "Drive addition failed"

# Add drives to the DRIVES containers
weka cluster container --no-header -F container=drives1 -o id | xargs -I {} -P${NUM_SERVERS} weka cluster drive add {} /dev/nvme5n1 /dev/nvme7n1 || assert "Drive addition failed"

#----------#
#  COMPUTE #
#----------#

# Join COMPUTE containers to the cluster
weka cluster container --no-header -o hostname,ips -F container=drives0 | xargs -n2 -P${NUM_SERVERS} -l bash -c 'weka cluster container add $0 --ip ${1}:14400' || assert "COMPUTE container addition failed"

# Join COMPUTE containers to the cluster
weka cluster container --no-header -o hostname,ips -F container=drives1 | xargs -n2 -P${NUM_SERVERS} -l bash -c 'weka cluster container add $0 --ip ${1}:14500' || assert "COMPUTE container addition failed"

#----------#
# FRONTEND #
#----------#

# Join frontend containers to the cluster
weka cluster container --no-header -o hostname,ips -F container=drives0 | xargs -n2 -P${NUM_SERVERS} -l bash -c 'weka cluster container add $0 --ip ${1}:14600' || assert "FRONTEND container addition failed"

# Configuration apply for FRONTEND
weka cluster container apply $(weka cluster container --no-header -F container=frontend0 -o id) --force

#Before start IO set override for cgroups, check hugepages values.
weka debug override add --key ionode_scheduling --value '"sched_other"'
#Increase scrubber rate
weka cluster update --scrubber-bytes-per-sec 1GiB
#Set protection and stripe width
weka cluster update --parity-drives 2 --data-drives 6
weka cluster update --cluster-name ${wekaclustername}
#Start IO
weka cluster start-io
weka debug traces retention set --server-max 70GB --server-ensure-free 10GB --client-max 10GB --client-ensure-free 10GB
weka cluster client-target-version set ${wekaversion}

#-----------------------#
#  Create file system   #
#-----------------------#

weka fs group create default
weka fs create Default default 8.07TiB # 8.07TiB is the size of the drives in the cluster, can get it from 'weka status' command

#-----------------------#
#  command to mount the Default fs to /weka   #
#-----------------------#

# run this on all nodes
# sudo sed -i '/weka/d' /etc/fstab; echo 'Default /weka wekafs x-systemd.requires=weka-agent.service,x-systemd.mount-timeout=infinity,_netdev 0 0' | sudo tee -a /etc/fstab; sudo mkdir -p /weka; sudo systemctl daemon-reload; sudo mount -a