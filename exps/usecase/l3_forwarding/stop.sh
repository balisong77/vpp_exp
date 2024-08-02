#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set +e

echo "Stop traffic and release VPP router & traffic generator instances..."

VPP_RT_PIDFILE="/run/vpp/rt/vpp_rt.pid"
VPP_TG_PIDFILE="/run/vpp/tg/vpp_tg.pid"

if [[ -f "${VPP_RT_PIDFILE}" ]];then
    sudo kill -9 "$(cat "${VPP_RT_PIDFILE}")"
    sudo rm "${VPP_RT_PIDFILE}"
fi

if [[ -f "${VPP_TG_PIDFILE}" ]];then
    sudo kill -9 "$(cat "${VPP_TG_PIDFILE}")"
    sudo rm "${VPP_TG_PIDFILE}"
fi
