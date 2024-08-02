#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -eo pipefail

echo "Stop VPP instance and iperf3 server..."

vpp_hs_pidfile="/run/vpp/vpp_hs.pid"
iperf3_pidfile="/run/iperf3.pid"

if [ -f "${vpp_hs_pidfile}" ];then
    sudo kill -9 "$(cat "${vpp_hs_pidfile}")"
    sudo rm "${vpp_hs_pidfile}"
fi

if [ -f "${iperf3_pidfile}" ];then
    sudo kill -9 "$(sudo cat "${iperf3_pidfile}" | tr -d '\0')"
    sudo rm "${iperf3_pidfile}"
fi
