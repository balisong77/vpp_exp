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
VPP_RUNTIME_DIR="/run/vpp/tg"
VPP_TG_PIDFILE="${VPP_RUNTIME_DIR}/vpp_tg.pid"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_tg.sock"

help_func()
{
    echo "Usage: ./run_vpp_tg.sh OPTS [ARGS]"
    echo "where OPTS := -c cpu core assignments"
    echo "           := -h help"
    echo "      ARGS := \"-c\" assign VPP main thread to a CPU core and place worker threads"
    echo "              on two isolated CPU cores, separated by comma"
    echo "              Example: -c <main_core,worker_core>"
    echo "Example:"
    echo "  ./run_vpp_tg.sh -c 1,2,3"
    echo
}

err_cleanup()
{
    echo "VPP software packet-generator setup error, cleaning up..."
    vpp_tg_pid=$(cat "${VPP_TG_PIDFILE}")
    sudo kill -9 "${vpp_tg_pid}"
    sudo rm "${VPP_TG_PIDFILE}"
    exit 1
}

options=(-o "hc:")
opts=$(getopt "${options[@]}" -- "$@")
eval set -- "$opts"

while true; do
    case "$1" in
      -h)
        help_func
        exit 0
        ;;
      -c)
        if ! [[ "$2" =~ ^[0-9]{1,3},[0-9]{1,3},[0-9]{1,3}$ ]]; then
            echo "error: \"-c\" requires correct isolated cpu core id"
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

check_vpp
check_vppctl

sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_TG_PIDFILE} }"   \
                     cpu "{ main-core ${main_core} corelist-workers ${worker_core} }"                          \
                     plugins "{ plugin dpdk_plugin.so { disable } }"

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

sudo "${vppctl_binary}" -s "${SOCKFILE}" create memif socket id 1 filename /tmp/memif_dut_1
sudo "${vppctl_binary}" -s "${SOCKFILE}" create int memif id 1 socket-id 1 rx-queues 1 tx-queues 1 master
sudo "${vppctl_binary}" -s "${SOCKFILE}" create memif socket id 2 filename /tmp/memif_dut_2
sudo "${vppctl_binary}" -s "${SOCKFILE}" create int memif id 1 socket-id 2 rx-queues 1 tx-queues 1 master
sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface mac address memif1/1 02:fe:a4:26:ca:ac
sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface mac address memif2/1 02:fe:51:75:42:ed
sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state memif1/1 up
sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state memif2/1 up
sudo "${vppctl_binary}" -s "${SOCKFILE}" \
'packet-generator new {
  name tg0
  limit -1
  worker 0
  size 60-60
  node memif1/1-output
  data {
      IP4: 00:00:0a:81:00:01 -> 00:00:0a:81:00:02
      UDP: 192.81.0.1  -> 192.81.0.2
      UDP: 1234 -> 2345
      incrementing 8
  }
}'

echo "Traffic generator starting up"
for _ in $(seq 5); do
    echo -n ".."
    sleep 1
done
echo " "

sudo "${vppctl_binary}" -s  "${SOCKFILE}" packet-generator enable-stream tg0

LOG=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show packet-generator)
if [[ "${LOG}" == *tg0* ]]; then
    echo "Successfully set up packet-generator!"
else
    echo "Failed to set up packet-generator!"
    err_cleanup
fi

echo "Done!"
