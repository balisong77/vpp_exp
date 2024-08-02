#!/usr/bin/env bash

# Copyright (c) 2022-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export vppctl_binary
export vpp_binary

DIR=$(dirname "$0")
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh
VPP_RUNTIME_DIR="/run/vpp/sw"
VPP_SW_PIDFILE="${VPP_RUNTIME_DIR}/vpp_sw.pid"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_sw.sock"

help_func()
{
    echo "Usage: ./run_vpp_sw.sh OPTS [ARGS]"
    echo "where  OPTS := -m L2 switching test via memif interface"
    echo "            := -p L2 switching test via physical NIC"
    echo "            := -c cpu core assignments"
    echo "            := -h help"
    echo "       ARGS := \"-p\" requires two physical NIC PCIe addresses, example: -p <inputNIC_PCIe_addr,outputNIC_PCIe_addr>"
    echo "               using \"lshw -c net -businfo\" get physical NIC PCIe address"
    echo "            := \"-c\" assign VPP main thread to a CPU core and place worker thread"
    echo "               on an isolated CPU core, separated by comma"
    echo "               Example: -c <main_core,worker_core>"
    echo "Example:"
    echo "  ./run_vpp_sw.sh -m -c 1,4"
    echo "  ./run_vpp_sw.sh -p 0001:01:00.0,0001:01:00.1 -c 1,4"
    echo
}

err_cleanup()
{
    echo "VPP setup error, cleaning up..."
    vpp_sw_pid=$(cat "${VPP_SW_PIDFILE}")
    sudo kill -9 "${vpp_sw_pid}"
    sudo rm "${VPP_SW_PIDFILE}"
    exit 1
}

memif_iface()
{
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state Ethernet0 up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state Ethernet1 up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface l2 bridge Ethernet0 1
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface l2 bridge Ethernet1 1
    sudo "${vppctl_binary}" -s "${SOCKFILE}" l2fib add 00:00:0A:81:0:2 1 Ethernet1 static

    LOG=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show interface)
    if [[ "${LOG}" == *Ethernet0* && "${LOG}" == *Ethernet1* ]]; then
        echo "Successfully set up memif!"
    else
        echo "Failed to set up memif!"
        err_cleanup
    fi
}

phy_iface()
{
    echo "Creating interfaces eth0[1/2]: ${PCIe_addr[0]}"
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state eth0 up
    echo "Creating interfaces eth1[2/2]: ${PCIe_addr[1]}"
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state eth1 up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface l2 bridge eth0 10
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface l2 bridge eth1 10
    sudo "${vppctl_binary}" -s "${SOCKFILE}" l2fib add 00:00:0a:81:00:02 10 eth1 static

    LOG=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show interface)
    if [[ "${LOG}" == *eth0* && "${LOG}" == *eth1* ]]; then
        echo "Successfully set up physical NIC interface!"
    else
        echo "Failed to set up physical NIC interface!"
        err_cleanup
    fi
}

options=(-o "hmp:c:")
opts=$(getopt "${options[@]}" -- "$@")
eval set -- "$opts"

while true; do
    case "$1" in
      -h)
          help_func
          exit 0
          ;;
      -m)
          MEMIF_IFACE="1"
          shift 1
          ;;
      -p)
          PHY_IFACE="1"
          PCIe_pattern='[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]'
          if ! [[ "$2" =~ ^${PCIe_pattern},${PCIe_pattern}$ ]];then
              echo "Incorrect PCIe addresses format: $2"
              help_func
              exit 1
          fi
          PCIe_addr[0]=$(echo "$2" | cut -d "," -f 1)
          PCIe_addr[1]=$(echo "$2" | cut -d "," -f 2)
          if [[ "${PCIe_addr[0]}" == "${PCIe_addr[1]}" ]]; then
              echo "error: \"-p\" option bad usage"
              help_func
              exit 1
          fi
          shift 2
          ;;
      -c)
          if ! [[ "$2" =~ ^[0-9]{1,3},[0-9]{1,3}$ ]]; then
              echo "error: \"-c\" requires correct cpu isolation core id"
              help_func
              exit 1
          fi
          main_core=$(echo "$2" | cut -d "," -f 1)
          worker_core=$(echo "$2" | cut -d "," -f 2)
          if [[ "${main_core}" == "${worker_core}" ]]; then
              echo "error: \"-c\" option bad usage"
              help_func
              exit 1
          fi
          shift 2
          ;;
      --)
          shift
          break
          ;;
      *)
          echo "Invalid Option!!"
          help_func
          exit 1
          ;;
    esac
done

if [[ "${MEMIF_IFACE}" && "${PHY_IFACE}" ]]; then
    echo "Don't support both -m and -p at the same time!!"
    help_func
    exit 1
fi

if ! [[ "${MEMIF_IFACE}" || "${PHY_IFACE}" ]]; then
    echo "require an option: \"-m\" or \"-p\""
    help_func
    exit 1
fi

check_vpp
check_vppctl

if [ -n "$MEMIF_IFACE" ]; then
    sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_SW_PIDFILE} }"   \
                         cpu "{ main-core ${main_core} corelist-workers ${worker_core} }"                             \
                         dpdk "{ no-pci dev default {num-tx-queues 1 num-rx-queues 1 } vdev net_memif0,role=client,id=1,socket-abstract=no,socket=/tmp/memif_dut_1,mac=02:fe:a4:26:ca:f2,zero-copy=yes vdev net_memif1,role=client,id=1,socket-abstract=no,socket=/tmp/memif_dut_2,mac=02:fe:51:75:42:42,zero-copy=yes }"

    echo "VPP starting up"
    for _ in $(seq 10); do
        echo -n "."
        sleep 1
    done

    if ! [[ $(sudo "${vppctl_binary}" -s "${SOCKFILE}" show threads) ]]; then
       echo "VPP startup failed!"
       exit 1
    fi

    echo " "
    echo "Setting memif interfaces..."
    memif_iface
fi

if [ -n "$PHY_IFACE" ]; then
    sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_SW_PIDFILE} }"      \
                         cpu "{ main-core ${main_core} corelist-workers ${worker_core} }"                             \
                         dpdk "{ dev ${PCIe_addr[0]} { name eth0 } dev ${PCIe_addr[1]} { name eth1 } }"

    echo "VPP starting up"
    for _ in $(seq 10); do
        echo -n "."
        sleep 1
    done

    if ! [[ $(sudo "${vppctl_binary}" -s "${SOCKFILE}" show threads) ]]; then
       echo "VPP startup failed!"
       exit 1
    fi

    echo " "
    echo "Setting physical NIC interfaces..."
    phy_iface
fi
echo "Done!"
