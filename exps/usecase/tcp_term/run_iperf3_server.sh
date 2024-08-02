#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export DIR
export DATAPLANE_TOP
export LOOP_BACK
export PHY_IFACE
export CORE_ID
export LDP_PATH

DIR=$(cd "$(dirname "$0")" || exit 1 ;pwd)
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh

help_func()
{
    echo "Usage: ./run_iperf3_server.sh OPTS [ARGS]"
    echo "where OPTS := -l iperf3 test via loopback interface"
    echo "           := -p iperf3 test via physical NIC"
    echo "           := -c set cpu affinity of iperf3 server"
    echo "           := -h help"
    echo "      ARGS := \"-c\" requires an isolated cpu core id, example: -c 2"
    echo "Example:"
    echo "  ./run_iperf3_server.sh -l -c 2"
    echo "  ./run_iperf3_server.sh -p -c 2"
    echo
}

options=(-o "hlpc:")
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
          shift 1
          ;;
      -c)
          if ! [[ "$2" =~ ^[0-9]{1,3}$ ]]; then
              echo "error: \"-c\" requires correct isolated cpu core id"
              help_func
              exit 1
          fi
          CORE_ID="$2"
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
      echo "requires an option: \"-l\" or \"-p\""
      help_func
      exit 1
fi

check_ldp

if [ -n "${LOOP_BACK}" ]; then
    VCL_IPERF_SERVER_CONF=vcl_iperf3_server_lb.conf
fi
if [ -n "${PHY_IFACE}" ]; then
    VCL_IPERF_SERVER_CONF=vcl_iperf3_server_pn.conf
fi

iperf3_pidfile=/run/iperf3.pid
echo "Starting iperf3 server..."
sudo taskset -c "${CORE_ID}" sh -c "LD_PRELOAD=${LDP_PATH} VCL_CONFIG=${DIR}/${VCL_IPERF_SERVER_CONF} iperf3 -4 -s -D -I ${iperf3_pidfile}"
echo "Done!!"
