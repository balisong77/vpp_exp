#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export vppctl_binary="/usr/local/bin/vppctl"
DIR=$(dirname "$0")
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh

# VPP cli socket文件位置
sockfile=/run/vpp/remote/cli_remote.sock

test_duration=3

check_vppctl

echo "=========="

sudo "${vppctl_binary}" -s "${sockfile}" clear runtime

echo "Letting IPSec work for ${test_duration} seconds:"
for _ in $(seq ${test_duration}); do
    echo -n "..$_"
    sleep 1
done

sudo "${vppctl_binary}" -s "${sockfile}" show runtime

echo
echo "END"
