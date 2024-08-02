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
    echo "Usage: ./run_nginx_server.sh OPTS [ARGS]"
    echo "where  OPTS := -l ssl reverse proxy test via loopback interface, NGINX over VPP"
    echo "            := -p ssl reverse proxy test via physical NIC, NGINX over kernel"
    echo "            := -c set cpu affinity of NGINX https server, example: -c 2"
    echo "            := -h help"
    echo "Example:"
    echo "  ./run_nginx_server.sh -l -c 2"
    echo "  ./run_nginx_server.sh -p -c 1"
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
              echo "error: \"-c\" requires correct isolated core id"
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

sudo mkdir -p /etc/nginx/certs

if ! [[ -e /etc/nginx/certs/server.key && -e /etc/nginx/certs/server.crt ]]; then
      echo "Creating ssl server's private key and certificate..."
      sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/certs/server.key -out /etc/nginx/certs/server.crt
      echo "Created successfully!"
fi

echo "ssl server's private key and certificate:"
ls "/etc/nginx/certs/server.key"
ls "/etc/nginx/certs/server.crt"

sudo mkdir -p /var/www/html

if ! [ -e /var/www/html/1kb ]; then
      echo "Creating 1kb load file"
      sudo dd if=/dev/urandom of=/var/www/html/1kb bs=1024 count=1
      echo "Created successfully!"
fi

echo "1kb load file:"
ls "/var/www/html/1kb"

VCL_SERVER_CONF=vcl_nginx_server.conf
NGINX_SERVER_CONF=nginx_server.conf

echo "=========="
echo "Starting Server"
if [ -n "$LOOP_BACK" ]; then
    check_ldp
    sudo taskset -c "${MAIN_CORE}" sh -c "LD_PRELOAD=${LDP_PATH} VCL_CONFIG=${DIR}/${VCL_SERVER_CONF} nginx -c ${DIR}/${NGINX_SERVER_CONF}"
fi
if [ -n "${PHY_IFACE}" ]; then
    sudo taskset -c "${MAIN_CORE}" sh -c "nginx -c ${DIR}/${NGINX_SERVER_CONF}"
fi
echo "Done!!"
