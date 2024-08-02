#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export DIR
export DATAPLANE_TOP
export CORE_ID
export LDP_PATH

DIR=$(cd "$(dirname "$0")" || exit 1 ;pwd)
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh

help_func()
{
    echo "Usage: ./run_iperf3_client.sh OPTS [ARGS]"
    echo "where  OPTS := -c set cpu affinity of iperf3 client"
    echo "            := -h help"
    echo "       ARGS := \"-c\" requires an isolated cpu core id, example: -c 3"
    echo "Example:"
    echo "  ./run_iperf3_client.sh -c 3"
    echo
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

check_ldp

echo "Starting iperf3 client..."
echo "========================="
sudo taskset -c "${CORE_ID}" sh -c "LD_PRELOAD=${LDP_PATH} VCL_CONFIG=${DIR}/vcl_iperf3_client.conf iperf3 -c 172.16.1.1"
