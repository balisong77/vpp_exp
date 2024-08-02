#!/usr/bin/env bash

# Copyright (c) 2022-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export vppctl_binary
export DIR
export DATAPLANE_TOP

DIR=$(cd "$(dirname "$0")" || exit 1 ;pwd)
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh

help_func()
{
    echo "Usage: ./traffic_monitor.sh"
    echo
}


while [ "$#" -gt "0" ]; do
    case "$1" in
      -h)
        help_func
	exit 0
	;;
      *)
        echo "Invalid Option!!"
	help_func
	exit 1
	;;
    esac
done

check_vppctl

sockfile="/run/vpp/sw/cli_sw.sock"

sudo "${vppctl_binary}" -s "${sockfile}" clear interfaces
sudo "${vppctl_binary}" -s "${sockfile}" clear runtime
echo "Letting VPP switch packets for 3 seconds:"
for _ in $(seq 3); do
    echo -n "..$_"
    sleep 1
done

echo " "
echo " "
echo "=========="
sudo "${vppctl_binary}" -s "${sockfile}" show interface
sudo "${vppctl_binary}" -s "${sockfile}" show runtime
