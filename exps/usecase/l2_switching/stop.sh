#!/usr/bin/env bash

# Copyright (c) 2022-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

echo "Stop traffic and release switch & traffic_generator instances..."

vpp_sw_pidfile="/run/vpp/sw/vpp_sw.pid"
vpp_tg_pidfile="/run/vpp/tg/vpp_tg.pid"

if [ -f "${vpp_sw_pidfile}" ];then
    sudo kill -9 "$(cat "${vpp_sw_pidfile}")"
    sudo rm "${vpp_sw_pidfile}"
fi

if [ -f "${vpp_tg_pidfile}" ];then
    sudo kill -9 "$(cat "${vpp_tg_pidfile}")"
    sudo rm "${vpp_tg_pidfile}"
fi
