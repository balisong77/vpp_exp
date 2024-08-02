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
VPP_RUNTIME_DIR="/run/vpp/tg"
VPP_PIDFILE="${VPP_RUNTIME_DIR}/vpp_tg.pid"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_tg.sock"
MEMIF_SOCKET1="/tmp/memif_dut_1"
MEMIF_SOCKET2="/tmp/memif_dut_2"

help_func()
{
    echo "Usage: ./run_vpp_tg.sh options"
    echo
    echo "Options:"
    echo "  -c <core list>       set CPU affinity. Assign VPP main thread to 1st core"
    echo "                       in list and place worker threads on other listed cores."
    echo "                       Cores are separated by commas, and worker cores can include"
    echo "                       ranges. The number of worker cores needs to be even."
    echo "  -f <count>           number of flows with different IP destination addresses"
    echo "                       to generate"
    echo "  -l <length>          octet length of generated Ethernet packets, 60-2048. 60 by"
    echo "                       default. 4 octets frame check sequence (FCS) is not counted"
    echo "                       into the length, nor is it generated. Larger packets may reduce"
    echo "                       VPP traffic generator performance. Changing the packet length"
    echo "                       via this option should not affect the performance."
    echo "  -h                   show this message and quit"
    echo
    echo "Example:"
    echo "  ./run_vpp_tg.sh -c 1,3-4,6,8 -f 10 -l 100"
    echo
}

err_cleanup()
{
    echo "VPP traffic generator startup error, cleaning up..."
    if [[ -f "${VPP_PIDFILE}" ]]; then
        vpp_tg_pid=$(cat "${VPP_PIDFILE}")
        sudo kill -9 "${vpp_tg_pid}"
        sudo rm "${VPP_PIDFILE}"
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

  echo ${count}
}

flows_num=10000
packet_len=60
options=(-o "hc:f:l:")
opts=$(getopt "${options[@]}" -- "$@")
eval set -- "$opts"

while true; do
    case "$1" in
      -h)
        help_func
        exit 0
        ;;
      -c)
        if ! [[ "$2" =~ ^[0-9]{1,3}((,[0-9]{1,3})|(,[0-9]{1,3}-[0-9]{1,3}))+$ ]]; then
            echo "error: \"-c\" requires correct isolated cpu core id"
            help_func
            exit 1
        fi
        main_core=$(echo "$2" | cut -d "," -f 1)
        worker_cores=$(echo "$2" | cut -d "," -f 2-)
        if [[ "${main_core}" == "${worker_cores}" ]]; then
            echo "error: \"-c\" requires different main core and worker core"
            help_func
            exit 1
        fi
        workers_count=$(cal_cores "$worker_cores")
        if [[ $((workers_count % 2)) -ne 0 ]]; then
            echo "error: \"-c\" requires an even number of worker cores"
            help_func
            exit 1
        fi
        queues_count=$((workers_count / 2))
        shift 2
        ;;
      -f)
        if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
            echo "error: \"-f\" requires correct number of flows"
            help_func
            exit 1
        fi
	flows_num=$2
        shift 2
        ;;
      -l)
        if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
            echo "error: \"-l\" requires octet length for generated packets"
            help_func
            exit 1
        fi
        if [[ "$2" -lt 60 ]] || [[ "$2" -gt 2048 ]]; then
            echo "error: \"-l\" requires a length between 60 and 2048."
            help_func
            exit 1
        fi
        packet_len=$2
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

check_vpp > /dev/null
check_vppctl > /dev/null
sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_PIDFILE} }"   \
                     cpu "{ main-core ${main_core} corelist-workers ${worker_cores} }"                         \
                     plugins "{ plugin default { disable } plugin memif_plugin.so { enable } }"
echo "VPP traffic generator starting up"
sleep 0.5

# Disable "Exit on Error" temporarily to allow vppctl to try connection several
# times for slow starting up VPP on some platforms.
set +e
max_conn_retries=10
for conn_count in $(seq ${max_conn_retries}); do
    if ! output=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show threads) ; then
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

sudo "${vppctl_binary}" -s "${SOCKFILE}" create memif socket id 1 filename ${MEMIF_SOCKET1}
sudo "${vppctl_binary}" -s "${SOCKFILE}" create int memif id 1 socket-id 1 rx-queues "${queues_count}" tx-queues "${queues_count}" master
sudo "${vppctl_binary}" -s "${SOCKFILE}" create memif socket id 2 filename ${MEMIF_SOCKET2}
sudo "${vppctl_binary}" -s "${SOCKFILE}" create int memif id 1 socket-id 2 rx-queues "${queues_count}" tx-queues "${queues_count}" master
sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface mac address memif1/1 02:fe:a4:26:ca:ac
sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface mac address memif2/1 02:fe:51:75:42:ed
sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state memif1/1 up
sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state memif2/1 up

start_dst_ip=1.0.0.1
start_dst_ip_int=$(echo "$start_dst_ip" | awk -F. '{ printf("%d", ($1 * 256^3) + ($2 * 256^2) + ($3 * 256) + $4) }')
end_dst_ip_int=$(( start_dst_ip_int + flows_num - 1 ))
end_dst_ip=$(( (end_dst_ip_int >> 24) & 255 )).$(( (end_dst_ip_int >> 16) & 255 )).$(( (end_dst_ip_int >> 8) & 255 )).$(( end_dst_ip_int & 255 ))

for ((worker_index=0; worker_index<queues_count; worker_index++)); do
    sudo "${vppctl_binary}" -s "${SOCKFILE}"  \
    "packet-generator new {
      name tg${worker_index}
      limit -1
      size ${packet_len}-${packet_len}
      worker ${worker_index}
      node memif1/1-output
      data {
          IP4: 00:00:0a:81:00:01 -> c6:ce:78:fe:5f:77
          UDP: 200.0.0.1  -> ${start_dst_ip} + ${end_dst_ip}
          UDP: 1234 -> 2345
          incrementing 8
      }
    }"
done

sudo "${vppctl_binary}" -s  "${SOCKFILE}" packet-generator enable-stream

echo
log=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show packet-generator)
if [[ "${log}" == *Yes* ]]; then
    echo "Successfully start VPP traffic generator!"
else
    err_cleanup
fi
