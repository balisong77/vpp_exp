#!/usr/bin/env bash 

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export vppctl_binary="/usr/local/bin/vppctl"
export vpp_binary="/usr/local/bin/vpp"

Ethernet0="Ethernet0"
Ethernet1="Ethernet1"

DIR=$(dirname "$0")
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh
VPP_RUNTIME_DIR="/run/vpp/remote"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_remote.sock"
VPP_REMOTE_PIDFILE="${VPP_RUNTIME_DIR}/vpp_remote.pid"
MEMIF_SOCKET1="/tmp/memif_ipsec_1"
MEMIF_SOCKET2="/tmp/memif_ipsec_2"

help_func()
{
    echo "Usage: ./run_vpp_remote.sh options"
    echo
    echo "Options:"
    echo "  -c <core list>       set CPU affinity. Assign VPP main thread to 1st core"
    echo "                       in list and place worker threads on other listed cores."
    echo "                       Cores are separated by commas, and worker cores can include ranges."
    echo "  -m                   test via VPP memif interface"
    echo "  -p <PCIe addresses>  test via DPDK physical NIC. Require one NIC PCIe address, connect to local machine"
    echo "  -h                   show this message and quit"
    echo
    echo "Example:"
    echo "  ./run_vpp_remote.sh -m -c 1,2,3"
    echo "  ./run_vpp_remote.sh -p 0001:01:00.1 -c 1,2,3"
    echo
}

err_cleanup()
{
    echo "Remote VPP setup error, cleaning up..."
    if [[ -f "${VPP_REMOTE_PIDFILE}" ]]; then
        vpp_remote_pid=$(cat "${VPP_REMOTE_PIDFILE}")
        sudo kill -9 "${vpp_remote_pid}"
        sudo rm "${VPP_REMOTE_PIDFILE}"
    fi
    exit 1
}
cal_cores()
{
  IFS=',' read -ra array <<< "$1"
  count=0

  for item in "${array[@]}"; do
      if [[ $item == *-* ]]; then
          start=${item%-*}
          end=${item#*-}
          count=$((count + end - start + 1))
      else
          count=$((count + 1))
      fi
  done

  echo $count
}
setup_iface()
{
    if [[ -n "$phy_iface" ]]; then
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state "${Ethernet0}" up
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ip address "${Ethernet0}" 10.12.0.5/16
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state "${Ethernet1}" up
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ip address "${Ethernet1}" 192.82.0.5/16
    elif [[ -n "$memif_iface" ]]; then
        sudo "${vppctl_binary}" -s "${SOCKFILE}" create memif socket id 1 filename ${MEMIF_SOCKET1}
        sudo "${vppctl_binary}" -s "${SOCKFILE}" create int memif id 1 socket-id 1 rx-queues 1 tx-queues 1 master
        sudo "${vppctl_binary}" -s "${SOCKFILE}" create memif socket id 2 filename ${MEMIF_SOCKET2}
        sudo "${vppctl_binary}" -s "${SOCKFILE}" create int memif id 1 socket-id 2 rx-queues 1 tx-queues 1 master
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state memif1/1 up
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ip address memif1/1 10.11.0.2/16
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state memif2/1 up
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ip address memif2/1 10.12.0.2/16
    fi

    LOG=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show interface)
    if [[ -n "$phy_iface" && "${LOG}" == *"${Ethernet0}"* ]]; then
        echo "Successfully set up interfaces!"
    elif [[ -n "$memif_iface" && "${LOG}" == *memif1/1* && "${LOG}" == *memif2/1* ]]; then
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
          PCIE_PATTERN='[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]'
          if ! [[ "$2" =~ ^${PCIE_PATTERN},${PCIE_PATTERN}$ ]];then
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
          queues_count=$(cal_cores "$worker_core")
        #   queues_count=1
          echo "queues_count: ""${queues_count}"
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
    sudo rm -f ${MEMIF_SOCKET1} ${MEMIF_SOCKET2}
    sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_REMOTE_PIDFILE} }"                                                              \
                         cpu "{ main-core ${main_core} corelist-workers ${worker_core} }"                                                                                            \
                         plugins "{ plugin default { disable } plugin memif_plugin.so { enable } plugin crypto_native_plugin.so {enable} plugin crypto_openssl_plugin.so {enable} }"

    echo "Remote VPP starting up"
fi

if [[ -n "$phy_iface" ]]; then
    sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_REMOTE_PIDFILE} }"                                                              \
                         cpu "{ main-core ${main_core} corelist-workers ${worker_core} }"                                                                                            \
                         plugins "{ plugin default { disable } plugin dpdk_plugin.so { enable } plugin crypto_native_plugin.so {enable} plugin crypto_openssl_plugin.so {enable} plugin ping_plugin.so { enable } plugin nat_plugin.so {enable}}"  \
                         dpdk "{ dev ${pcie_addr[0]} { name "${Ethernet0}" num-tx-queues ${queues_count} num-rx-queues ${queues_count}} 
                                 dev ${pcie_addr[1]} { name "${Ethernet1}" num-tx-queues ${queues_count} num-rx-queues ${queues_count}}}"

    echo "Remote VPP starting up"
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

echo "Setting up DPDK interfaces..."
setup_iface

echo " "
echo "Successfully start remote VPP instance!"
