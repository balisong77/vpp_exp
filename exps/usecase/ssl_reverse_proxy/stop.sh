#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

echo "Stop VPP instance, NGINX proxy & server..."

vpp_proxy_pidfile="/run/vpp/vpp_proxy.pid"
nginx_server_pidfile="/run/nginx_server.pid"
nginx_proxy_pidfile="/run/nginx_proxy.pid"

if [ -f "${vpp_proxy_pidfile}" ];then
    sudo kill -9 "$(cat "${vpp_proxy_pidfile}")"
    sudo rm "${vpp_proxy_pidfile}"
fi

if [ -f "${nginx_server_pidfile}" ];then
    readarray -t nginx_server_workers < <(pgrep -P "$(cat "${nginx_server_pidfile}")" nginx)
    sudo kill -9 "${nginx_server_workers[@]}"
    sudo kill -9 "$(cat "${nginx_server_pidfile}")"
    sudo rm "${nginx_server_pidfile}"
fi

if [ -f "${nginx_proxy_pidfile}" ];then
    readarray -t nginx_proxy_workers < <(pgrep -P "$(cat "${nginx_proxy_pidfile}")" nginx)
    sudo kill -9 "${nginx_proxy_workers[@]}"
    sudo kill -9 "$(cat "${nginx_proxy_pidfile}")"
    sudo rm "${nginx_proxy_pidfile}"
fi
