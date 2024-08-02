#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export vppctl_binary="/usr/local/bin/vppctl_exp"
export vpp_binary="/usr/local/bin/vpp_exp"

Ethernet0="Ethernet0"
Ethernet1="Ethernet1"

DIR=$(dirname "$0")
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh
VPP_RUNTIME_DIR="/run/vpp/remote"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_remote.sock"
# 建立IPSec隧道的网卡
intf="${Ethernet0}"

#配置最简单的L3转发, fwd流量转回node3
sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 192.82.0.2/32 via 192.82.0.100 "${Ethernet1}"
sudo "${vppctl_binary}" -s "${SOCKFILE}" set ip neighbor "${Ethernet1}" 192.82.0.100 04:3f:72:f4:40:4a

echo "Simple L3 configuration successful!"