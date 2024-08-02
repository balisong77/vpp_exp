#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

echo "Stop VPP instances..."

VPP_LOCAL_PIDFILE="/run/vpp/local/vpp_local.pid"
VPP_REMOTE_PIDFILE="/run/vpp/remote/vpp_remote.pid"

if [[ -f "${VPP_LOCAL_PIDFILE}" ]];then
    sudo kill -9 "$(cat "${VPP_LOCAL_PIDFILE}")"
    sudo rm "${VPP_LOCAL_PIDFILE}"
fi

if [[ -f "${VPP_REMOTE_PIDFILE}" ]];then
    sudo kill -9 "$(cat "${VPP_REMOTE_PIDFILE}")"
    sudo rm "${VPP_REMOTE_PIDFILE}"
fi
