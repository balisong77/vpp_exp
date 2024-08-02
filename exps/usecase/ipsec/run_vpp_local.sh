#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export vppctl_binary
export vpp_binary

DIR=$(dirname "$0")
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh
VPP_RUNTIME_DIR="/run/vpp/local"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_local.sock"
VPP_LOCAL_PIDFILE="${VPP_RUNTIME_DIR}/vpp_local.pid"
MEMIF_SOCKET1="/tmp/memif_ipsec_1"
MEMIF_SOCKET2="/tmp/memif_ipsec_2"

help_func()
{
    echo "Usage: ./run_vpp_local.sh <options>"
    echo
    echo "Options:"
    echo "  -c <core list>       set CPU affinity. Assign VPP main thread to 1st core"
    echo "                       in list and place worker threads on other listed cores."
    echo "                       Cores are separated by commas, and worker cores can include ranges."
    echo "  -m                   test via DPDK+VPP memif interface"
    echo "  -p <PCIe addresses>  test via DPDK physical NIC. Requires two NIC PCIe addresses, separated by comma"
    echo "                       1st NIC connect to traffic generator, 2nd NIC connect to remote machine"
    echo "  -h                   show this message and quit"
    echo
    echo "Example:"
    echo "  ./run_vpp_local.sh -m -c 4,5"
    echo "  ./run_vpp_local.sh -p 0001:01:00.0,0001:01:00.1 -c 4,5"
    echo
}

err_cleanup()
{
    echo "Local VPP setup error, cleaning up..."
    if [[ -f "${VPP_LOCAL_PIDFILE}" ]]; then
        vpp_local_pid=$(cat "${VPP_LOCAL_PIDFILE}")
        sudo kill -9 "${vpp_local_pid}"
        sudo rm "${VPP_LOCAL_PIDFILE}"
    fi
    exit 1
}

setup_iface()
{
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state Ethernet0 up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state Ethernet1 up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ip address Ethernet0 10.11.0.1/16
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ip address Ethernet1 10.12.0.1/16

    LOG=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show interface)
    if [[ "${LOG}" == *Ethernet0* && "${LOG}" == *Ethernet1* ]]; then
        echo "Successfully set up interfaces!"
    else
        echo "Failed to set up interfaces!"
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
          memif_iface="1"
          shift 1
          ;;
      -p)
          phy_iface="1"
          PCIe_pattern='[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]'
          if ! [[ "$2" =~ ^${PCIe_pattern},${PCIe_pattern}$ ]];then
              echo "Incorrect PCIe addresses format: $2"
              help_func
              exit 1
          fi
          pcie_addr[0]=$(echo "$2" | cut -d "," -f 1)
          pcie_addr[1]=$(echo "$2" | cut -d "," -f 2)
          if [[ "${pcie_addr[0]}" == "${pcie_addr[1]}" ]]; then
              echo "error: \"-p\" option bad usage"
              help_func
              exit 1
          fi
          shift 2
          ;;
      -c)
          if ! [[ "$2" =~ ^[0-9]{1,3}((,[0-9]{1,3})|(,[0-9]{1,3}-[0-9]{1,3}))+$ ]]; then
              echo "error: \"-c\" requires correct cpu isolation core id"
              help_func
              exit 1
          fi
          main_core=$(echo "$2" | cut -d "," -f 1)
          worker_core=$(echo "$2" | cut -d "," -f 2-)
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

if [[ "${memif_iface}" && "${phy_iface}" ]]; then
    echo "Don't support both -m and -p at the same time!!"
    help_func
    exit 1
fi

if ! [[ "${memif_iface}" || "${phy_iface}" ]]; then
    echo "require an option: \"-m\" or \"-p\""
    help_func
    exit 1
fi

if ! [[ "${main_core}" && "${worker_core}" ]]; then
    echo "require an option: \"-c\""
    help_func
    exit 1
fi

check_vpp
check_vppctl

if [[ -n "$memif_iface" ]]; then
    sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_LOCAL_PIDFILE} }"                                                                  \
                         cpu "{ main-core ${main_core} corelist-workers ${worker_core} }"                                                                                               \
                         plugins "{ plugin default { disable } plugin dpdk_plugin.so { enable } plugin crypto_native_plugin.so {enable} plugin crypto_openssl_plugin.so {enable} }"     \
                         dpdk "{ no-pci dev default {num-tx-queues 1 num-rx-queues 1 } vdev net_memif0,role=client,id=1,socket-abstract=no,socket=${MEMIF_SOCKET1},mac=02:fe:a4:26:ca:ac,zero-copy=yes vdev net_memif1,role=client,id=1,socket-abstract=no,socket=${MEMIF_SOCKET2},mac=02:fe:a4:26:ca:ad,zero-copy=yes }"

    echo "Local VPP starting up"
fi

if [[ -n "$phy_iface" ]]; then
    sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_LOCAL_PIDFILE} }"                                                                  \
                         cpu "{ main-core ${main_core} corelist-workers ${worker_core} }"                                                                                               \
                         plugins "{ plugin default { disable } plugin dpdk_plugin.so { enable } plugin crypto_native_plugin.so {enable} plugin crypto_openssl_plugin.so {enable} }"     \
                         dpdk "{ dev ${pcie_addr[0]} { name Ethernet0 } dev ${pcie_addr[1]} { name Ethernet1 } }"

    echo "Local VPP starting up"
fi

sleep 0.5
# Disable "Exit on Error" temporarily to allow vppctl to try connection several
# times for slow starting up VPP on some platforms.
set +e
max_conn_retries=10
for conn_count in $(seq ${max_conn_retries}); do
    if ! output=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show threads); then
        if [[ ${conn_count} -eq ${max_conn_retries} ]]; then
            err_cleanup
        fi
        sleep 0.5
    elif [[ -z "${output}" ]]; then
        err_cleanup
    else
        break
    fi
done
set -e

echo " "
echo "Setting up DPDK interfaces..."

setup_iface

echo "Successfully start local VPP instance!"
