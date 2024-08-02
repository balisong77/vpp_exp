#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export vppctl_binary
export vpp_binary
export DIR
export DATAPLANE_TOP
export MAIN_CORE
export LOOP_BACK
export PHY_IFACE
export PCIe_addr

DIR=$(cd "$(dirname "$0")" || exit 1 ;pwd)
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh

help_func()
{
    echo
    echo "Usage: ./run_vpp_hs.sh OPTS [ARGS]"
    echo "where OPTS := -l iperf3 test via loopback interface"
    echo "           := -p iperf3 test via physical NIC"
    echo "           := -c cpu core assignments"
    echo "           := -h help"
    echo "      ARGS := \"-p\" requires a physical NIC PCIe address, example: -p 0001:01:00.0"
    echo "              using \"lshw -c net -businfo\" get physical NIC PCIe address"
    echo "           := \"-c\" assign VPP main thread to a CPU core, example: -c 1"
    echo "Example:"
    echo "  ./run_vpp_hs.sh -l -c 1"
    echo "  ./run_vpp_hs.sh -p 0001:01:00.0 -c 1"
    echo
}

err_cleanup()
{
    echo "VPP setup error, cleaning up..."
    vpp_hs_pid=$(cat "${vpp_hs_pidfile}")
    sudo kill -9 "${vpp_hs_pid}"
    sudo rm "${vpp_hs_pidfile}"
    exit 1
}

loop_back()
{
    sudo "${vppctl_binary}" -s "${sockfile}" create loopback interface
    sudo "${vppctl_binary}" -s "${sockfile}" set interface state loop0 up
    sudo "${vppctl_binary}" -s "${sockfile}" create loopback interface
    sudo "${vppctl_binary}" -s "${sockfile}" set interface state loop1 up
    sudo "${vppctl_binary}" -s "${sockfile}" ip table add 1
    sudo "${vppctl_binary}" -s "${sockfile}" set interface ip table loop0 1
    sudo "${vppctl_binary}" -s "${sockfile}" ip table add 2
    sudo "${vppctl_binary}" -s "${sockfile}" set interface ip table loop1 2
    sudo "${vppctl_binary}" -s "${sockfile}" set interface ip address loop0 172.16.1.1/24
    sudo "${vppctl_binary}" -s "${sockfile}" set interface ip address loop1 172.16.2.1/24
    sudo "${vppctl_binary}" -s "${sockfile}" app ns add id server secret 1234 if loop0
    sudo "${vppctl_binary}" -s "${sockfile}" app ns add id client secret 5678 if loop1
    sudo "${vppctl_binary}" -s "${sockfile}" ip route add 172.16.1.1/32 table 2 via lookup in table 1
    sudo "${vppctl_binary}" -s "${sockfile}" ip route add 172.16.2.1/32 table 1 via lookup in table 2

    LOG=$(sudo "${vppctl_binary}" -s "${sockfile}" show interface addr)
    if [[ "${LOG}" == *loop0* && "${LOG}" == *loop1* && "${LOG}" == *172.16.1.1/24* && "${LOG}" == *172.16.2.1/24* ]]; then
        echo "Successfully set up loopback interface!"
    else
        echo "Failed to set up loopback interface!"
        err_cleanup
    fi
}

phy_iface()
{
    echo "Creating interface eth0: ${PCIe_addr}"
    sudo "${vppctl_binary}" -s "${sockfile}" set interface ip address eth0 172.16.3.1/24
    sudo "${vppctl_binary}" -s "${sockfile}" set interface state eth0 up

    LOG=$(sudo "${vppctl_binary}" -s "${sockfile}" show interface addr)
    if [[ "${LOG}" == *eth0* && "${LOG}" == *172.16.3.1/24* ]]; then
        echo "Successfully set up physical NIC interface!"
    else
        echo "Failed to set up physical NIC interface!"
        err_cleanup
    fi
}

options=(-o "hlp:c:")
opts=$(getopt "${options[@]}" -- "$@")
eval set -- "$opts"

while true; do
    case "$1" in
      -h)
          help_func
          exit 0
          ;;
      -l)
          LOOP_BACK="1"
          shift 1
          ;;
      -p)
          PHY_IFACE="1"
          PCIe_pattern='[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]'
          if ! [[ "$2" =~ ^${PCIe_pattern}$ ]];then
              echo "Incorrect PCIe addresses format: $2"
              help_func
              exit 1
          fi
          PCIe_addr="$2"
          shift 2
          ;;
      -c)
          if ! [[ "$2" =~ ^[0-9]{1,3}$ ]]; then
              echo "error: \"-c\" requires correct isolated cpu core id"
              help_func
              exit 1
          fi
          MAIN_CORE="$2"
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

if [[ "${LOOP_BACK}" && "${PHY_IFACE}" ]]; then
      echo "Don't support set both -l and -p at the same time!!"
      help_func
      exit 1
fi

if ! [[ "${LOOP_BACK}" || "${PHY_IFACE}" ]]; then
      echo "require an option: \"-l\" or \"-p\""
      help_func
      exit 1
fi

check_vpp
check_vppctl

sockfile="/run/vpp/cli.sock"
vpp_hs_pidfile="/run/vpp/vpp_hs.pid"

if [ -n "${LOOP_BACK}" ]; then
    sudo "${vpp_binary}" unix "{ cli-listen ${sockfile} pidfile ${vpp_hs_pidfile} }"  \
                       cpu "{ main-core ${MAIN_CORE} }"                               \
                       tcp "{ cc-algo cubic }"                                        \
                       session "{ enable use-app-socket-api }"                        \
                       plugins "{ plugin dpdk_plugin.so { disable } }"

    echo "VPP starting up"
    for _ in $(seq 10); do
        echo -n "."
        sleep 1
    done

    if ! [[ $(sudo "${vppctl_binary}" -s "${sockfile}" show threads) ]]; then
       echo "VPP startup failed!"
       exit 1
    fi

    echo " "
    echo "Setting loopback interfaces..."
    loop_back
fi

if [ -n "${PHY_IFACE}" ]; then
    sudo "${vpp_binary}" unix "{ cli-listen ${sockfile} pidfile ${vpp_hs_pidfile} }"  \
                       cpu "{ main-core ${MAIN_CORE} }"                               \
                       tcp "{ cc-algo cubic }"                                        \
                       session "{ enable use-app-socket-api }"                        \
                       dpdk "{ dev ${PCIe_addr} { name eth0 } }"

    echo "VPP starting up"
    for _ in $(seq 10); do
        echo -n "."
        sleep 1
    done

    if ! [[ $(sudo "${vppctl_binary}" -s "${sockfile}" show threads) ]]; then
       echo "VPP startup failed!"
       exit 1
    fi

    echo " "
    echo "Setting physical NIC interface..."
    phy_iface
fi
echo "Done!!"
