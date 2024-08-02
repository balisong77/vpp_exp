#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export DIR
export DATAPLANE_TOP
export LOOP_BACK
export PHY_IFACE
export MAIN_CORE
export LDP_PATH

help_func()
{
    echo "Usage: ./run_wrk.sh OPTS [ARGS]"
    echo "where  OPTS := -l ssl reverse proxy test via loopback interface, wrk2 over VPP"
    echo "            := -p ssl reverse proxy test via physical NIC, wrk2 over kernel"
    echo "            := -c set cpu affinity of wrk, example: -c 4"
    echo "            := -h help"
    echo "Example:"
    echo "  ./run_wrk.sh -l -c 4"
    echo "  ./run_wrk.sh -p -c 4"
    echo
}

DIR=$(cd "$(dirname "$0")" || exit 1 ;pwd)
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh
wrk_binary=${DATAPLANE_TOP}/tools/traffic-gen/wrk2-aarch64/wrk

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
      echo "Don't support both -l and -p at the same time!!"
      help_func
      exit 1
fi

if ! [[ "${LOOP_BACK}" || "${PHY_IFACE}" ]]; then
      echo "requires an option: \"-l\" or \"-p\""
      help_func
      exit 1
fi

check_ldp

if ! [[ $(command -v "${wrk_binary}") ]]; then
      echo
      echo "Can't find wrk2 at: ${wrk_binary}"
      echo
      exit 1
fi

echo "Found wrk2 at: $(command -v "${wrk_binary}")"

echo "=========="
echo "Starting wrk2 test..."
echo ""

VCL_WRK_CONF=vcl_wrk2.conf
if [ -n "${LOOP_BACK}" ]; then
    sudo taskset -c "${MAIN_CORE}" sh -c "LD_PRELOAD=${LDP_PATH} VCL_CONFIG=${DIR}/${VCL_WRK_CONF} ${wrk_binary} --rate 100000000 -t 1 -c 12 -d 60s https://172.16.2.1:8089/1kb"
fi

if [ -n "${PHY_IFACE}" ]; then
    sudo taskset -c "${MAIN_CORE}" sh -c "${wrk_binary} --rate 100000000 -t 1 -c 12 -d 60s https://172.16.2.1:8089/1kb"
fi

echo ""
echo "Done!!"
