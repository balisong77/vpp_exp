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
    echo "Usage: ./run_nginx_proxy.sh OPTS [ARGS]"
    echo "where  OPTS := -l ssl reverse proxy test via loopback interface"
    echo "            := -p ssl reverse proxy test via physical NIC"
    echo "            := -c set cpu affinity of NGINX proxy server, example: -c 3"
    echo "            := -h help"
    echo "Example:"
    echo "  ./run_nginx_proxy.sh -l -c 3"
    echo "  ./run_nginx_proxy.sh -p -c 3"
    echo
}

DIR=$(cd "$(dirname "$0")" || exit 1 ;pwd)
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh

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

sudo mkdir -p /etc/nginx/certs

if ! [[ -e /etc/nginx/certs/proxy.key && -e /etc/nginx/certs/proxy.crt ]]; then
        echo "Creating ssl proxy's private key and certificate..."
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/certs/proxy.key -out /etc/nginx/certs/proxy.crt
        echo "Created successfully!"
fi

echo "ssl proxy's private key and certificate:"
ls "/etc/nginx/certs/proxy.key"
ls "/etc/nginx/certs/proxy.crt"

VCL_PROXY_CONF=vcl_nginx_proxy.conf
if [ "${PHY_IFACE}" ]; then
    VCL_PROXY_CONF=vcl_nginx_proxy_pn.conf
fi
NGINX_PROXY_CONF=nginx_proxy.conf

echo "=========="
echo "Starting Proxy"
sudo taskset -c "${MAIN_CORE}" sh -c "LD_PRELOAD=${LDP_PATH} VCL_CONFIG=${DIR}/${VCL_PROXY_CONF} nginx -c ${DIR}/${NGINX_PROXY_CONF}"
echo "Done!!"
