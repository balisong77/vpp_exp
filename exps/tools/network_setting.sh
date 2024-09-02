#!/bin/bash

#config offloading
#https://docs.kernel.org/networking/segmentation-offloads.html

function gso_on() {
    nic=$1
    sudo ethtool -K $nic gso on
}

function gso_off() {
    nic=$1
    sudo ethtool -K $nic gso off
}

function echo_gso {
    sudo ethtool -k $nic | grep generic-segmentation-offload
}

function tso_on() {
    nic=$1
    sudo ethtool -K $nic tso on
}

function tso_off() {
    nic=$1
    sudo ethtool -K $nic tso off
}

function echo_tso {
    sudo ethtool -k $nic | grep tcp-segmentation-offload
}

function gro_on() {
    nic=$1
    sudo ethtool -K $nic gro on
}

function gro_off() {
    nic=$1
    sudo ethtool -K $nic gro off
}

function echo_gro {
    sudo ethtool -k $nic | grep generic-receive-offload
}

function lro_on() {
    nic=$1
    sudo ethtool -K $nic lro on
}

function lro_off() {
    nic=$1
    sudo ethtool -K $nic lro off
}

function echo_lro {
    sudo ethtool -k $nic | grep large-receive-offload
}

#checksum offloading

function tx_csum_offloading_on() {
    nic=$1
    sudo ethtool -K $nic tx on
}

function tx_csum_offloading_off() {
    nic=$1
    sudo ethtool -K $nic tx off
}

function echo_tx_csum_offloading() {
    sudo ethtool -k $nic | grep tx-checksumming
}

function rx_csum_offloading_on() {
    nic=$1
    sudo ethtool -K $nic rx on
}

function rx_csum_offloading_off() {
    nic=$1
    sudo ethtool -K $nic rx off
}

function echo_rx_csum_offloading() {
    sudo ethtool -k $nic | grep rx-checksumming
}

function echo_offloading() {
    echo_tx_csum_offloading $1
    echo_rx_csum_offloading $1
    echo_gso $1
    echo_tso $1
    echo_gro $1
    echo_lro $1
}

#scaling setting
#config multi queue 
#config RSS

function set_nic_queue_num() {
    nic=$1
    num=$2
    sudo ethtool -L $nic combined $num
}

function get_nic_queue_num() {
    sudo ethtool -l $1 | awk 'END{print $2}'
}

function get_nic_rx_irq() {
    nic=$1
    rx_num=$2 
    pattern="${nic}-.*[rR][xX].*-${rx_num}$"
    #cat /proc/interrupts | awk '{print $NF}' | grep -e "${nic}-.*[rR][xX].*-${rx_num}$" | awk '{sub(":", "", $1); print $1}'
    cat  /proc/interrupts | awk '{if (match($NF, "'${pattern}'")) {sub(":", "", $1); print $1}}' 
}

function parse_cpu_map() {
    cpumap=$(echo $1 | sed 's/[0,]*//' | sed 's/,//g' | tr '[:lower:]' '[:upper:]')
    if [[ -z $cpumap ]]; then
        echo 0
        return 0
    fi
    cpumap=$(echo "obase = 10 ; ibase = 16 ; $cpumap " | bc)
    count=0
    cpus=""
    while (( $cpumap > 0 ));
    do 
        test_bit=$(( ${cpumap} & 1 ))
        if (( $test_bit == 1 )); then
           cpus="$cpus cpu${count}" 
        fi
        cpumap=$(( $cpumap >> 1 ))
        count=$(( $count + 1 ))
    done 
    echo $cpus
}

function make_cpu_map() {
    cpumap=0
    for cpu in "$@"
    do
        if [[ $cpu =~ "^[0-9]+-[0-9]+$" ]]; then 
            #this is a cpu list 
            for subcpu in $(eval "echo {$(echo $cpu | sed 's/-/../g')}")
            do 
                cpuflag=$(( 1 << $subcpu ))
                cpumap=$(( $cpumap | $cpuflag ))
            done 
        elif [[  $cpu =~ "^[0-9]+$" ]]; then 
            cpuflag=$(( 1 << $cpu ))
            cpumap=$(( $cpumap | $cpuflag ))
        else
            echo "invald $cpu"
            exit -1
        fi 
    done 
    echo $(echo "obase = 16 ; ibase = 10 ; $cpumap "|bc)
}

function __set_nic_rx_affinity() {
    nic=$1
    rx_num=$2
    cpumap=$3
    #get interrupt id
    irq=$(get_nic_rx_irq $nic $rx_num)
    #su - root -c "echo $cpumap > /proc/irq/${irq}/smp_affinity"
    echo $cpumap > /proc/irq/${irq}/smp_affinity
    #echo "set irq $irq with affinity $cpumap"
}

function set_nic_rx_affinity() {
    #nic
    #rx_num
    #input cpus
    #eg set_rx_affinity nic rx 0 1 2 3 
    nic=$1
    rx_num=$2
    cpumap=$(make_cpu_map ${@:3})
    __set_nic_rx_affinity $nic $rx_num $cpumap
}

function __get_nic_rx_affinity() {
    nic=$1
    rx_num=$2
    #get interrupt id
    irq=$(get_nic_rx_irq $nic $rx_num)
    pushd /proc/irq/${irq} > /dev/null
    cpumap=$(cat smp_affinity)
    popd > /dev/null
    echo $cpumap
}

function get_nic_rx_affinity() {
    parse_cpu_map $(__get_nic_rx_affinity $1 $2)
}

#config RPS
function __set_nic_rx_rps_cpus() {
    nic=$1
    rx_num=$2
    cpumap=$3
    su - root -c "echo $cpumap > /sys/class/net/${nic}/queues/rx-${rx_num}/rps_cpus"
}

function set_nic_rx_rps_cpus() {
    cpumap=$(make_cpu_map ${@:3})
    __set_nic_rx_rps_cpus $1 $2 $cpumap
}

function __get_nic_rx_rps_cpus() {
    nic=$1
    rx_num=$2
    echo $(cat /sys/class/net/${nic}/queues/rx-${rx_num}/rps_cpus)
}

function get_nic_rx_rps_cpus() {
    parse_cpu_map $(__get_nic_rx_rps_cpus $1 $2)
}

function nic_rx_rps_off() {
    __set_nic_rx_rps_cpus $1 $2 0
}

function set_rps_sock_flow_entries() {
    sudo echo $1 > /proc/sys/net/core/rps_sock_flow_entries
}

function set_rps_dev_flow_cnt() {
    #nic
    #rx
    #count 
    sudo echo $3 > /sys/class/net/$1/queues/rx-$2/rps_flow_cnt
}

function rfs_off {
    set_rps_sock_flow_entries 0
}

function set_mtu() {
    sudo ifconfig $1 mtu $2
}

#set multi queue 

function set_nic_vf() {
    su - root -c "echo 0 > /sys/class/net/$1/device/sriov_numvfs && echo $2  > /sys/class/net/$1/device/sriov_numvfs"
}

function get_nic_pci_businfo() {
    #nic
    ethtool -i $1 | awk '/bus-info:/{print $2}'
}

function get_pci_numa_node() {
    #pci businfo 
    lspci -s $1 -vv | awk -F ":" '/NUMA node:/{print $2}'
}

function get_nic_numa_node() {
    #nic 
    businfo=$(get_nic_pci_businfo $1)
    get_pci_numa_node $businfo
}

function get_nic_cpumap() {
    num=$(expr $(get_nic_queue_num $1) - 1)
    cpumask=0
    for i in $(eval "echo {0..$num}");
    do 
        cpumap=$(__get_nic_rx_affinity $1 $i)
        cpumap=$(echo $cpumap | sed 's/[0,]*//' | sed 's/,//g')
        if [[ -z $cpumap ]]; then
            cpumap=0
        fi
        cpumap=$(echo "obase = 10 ; ibase = 16 ; $cpumap "|bc)
        cpumask=$(( cpumask | $cpumap ))
    done 
    cpumask=$(echo "obase = 16 ; ibase = 10 ; $cpumask "|bc)
    echo $cpumask
}

function echo_network_configs() {
    nic=$1
    queue_num=$(get_nic_queue_num $nic)
    echo current network configuration of $nic
    echo_offloading $1
    echo queue_num: $queue_num
    echo rss_info:
    for rx in $(seq 0 `expr $queue_num - 1`);
    do
        echo -e "  rx_$rx:" "$(get_nic_rx_affinity $nic $rx)"
    done 
    echo rps_info:
    for rx in $(seq 0 `expr $queue_num - 1`);
    do
        echo -e "  rx_$rx:" "$(get_nic_rx_rps_cpus $nic $rx)"
    done 
    echo rfs_info: 
    echo -e "  rps_sock_flow_entries:" $(cat /proc/sys/net/core/rps_sock_flow_entries)
    
}
#XPS
