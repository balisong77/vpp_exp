#!/usr/bin/env bash

# Copyright (c) 2023-2024, Arm Limited.
#
# SPDX-License-Identifier: Apache-2.0

set -e

export vppctl_binary
export vpp_binary

DIR=$(dirname "$0")
DATAPLANE_TOP=${DIR}/../..
# shellcheck source=../../tools/check-path.sh
. "${DATAPLANE_TOP}"/tools/check-path.sh
VPP_RUNTIME_DIR="/run/vpp/local"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_local.sock"
intf=Ethernet1

help_func()
{
    echo "Usage: ./ipsec_local_setup.sh options"
    echo
    echo "Options:"
    echo "  -e <crypto engine>             set crypto engine: native/openssl"
    echo "  -a <crypto algorithm>          set crypto algorithm: aes-gcm-128/aes-gcm-256"
    echo "  -m                             test via DPDK memif interface"
    echo "  -p                             test via DPDK physical NIC"
    echo "  -h                             show this message and quit"
    echo "  --config <IPSec config>        Select VPP's IPSec config: policy/protection"
    echo
    echo "Example:"
    echo "  ./ipsec_local_setup.sh -m -e native -a aes-gcm-128 --config policy"
    echo
}

options=(-o "mphe:a:")
options+=(-l "config:")
opts=$(getopt "${options[@]}" -- "$@")
eval set -- "$opts"

while true; do
    case "$1" in
      -h)
          help_func
          exit 0
          ;;
      -e)
          crypto_engine="$2"
          shift 2
          ;;
      -a)
          crypto_alg="$2"
          crypto_algkey=4a506a794f574265564551694d653768
          if [[ ${crypto_alg} == "aes-gcm-256" ]]; then
              crypto_algkey=4a506a794f574265564551694d6537684a506a794f574265564551694d653768
          fi
          shift 2
          ;;
      -m)
          memif_iface="1"
          shift 1
          ;;
      -p)
          phy_iface="1"
          shift 1
          ;;
      --config)
          config="$2"
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

if ! [[ "${crypto_engine}" ]]; then
    echo "require crypto engine"
    help_func
    exit 1
fi

if ! [[ "${crypto_alg}" ]]; then
    echo "require crypto algorithm"
    help_func
    it 1
fi

if [[ "${memif_iface}" && "${phy_iface}" ]]; then
    echo "Don't support both -m and -p at the same time!!"
    help_func
    exit 1
fi

check_vppctl

sudo "${vppctl_binary}" -s "${SOCKFILE}" set crypto handler all "${crypto_engine}"

if [[ "${config}" == "policy" ]]; then
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec spd add 1001
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ipsec spd "${intf}" 1001
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec sa add 2000 spi 20002000 esp tunnel src 192.161.0.1 dst 192.162.0.1 crypto-alg "${crypto_alg}" crypto-key "${crypto_algkey}" salt 0x12345678
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec policy add spd 1001 priority 10 outbound action protect sa 2000 local-ip-range 192.81.0.1 - 192.81.0.255 remote-ip-range 192.82.0.1 - 192.82.0.255
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec policy add spd 1001 priority 100 outbound action bypass protocol 50
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 192.82.0.0/16 via 10.12.0.2 ${intf}
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 192.162.0.0/16 via 10.12.0.2 ${intf}
fi

if [[ "${config}" == "protection" ]]; then
    sudo "${vppctl_binary}" -s "${SOCKFILE}" create loopback interface
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state loop0 up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int ip addr loop0 192.161.0.1/32
    sudo "${vppctl_binary}" -s "${SOCKFILE}" create ipip tunnel src 192.161.0.1 dst 192.162.0.1
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec sa add 0 spi 100000 crypto-key "${crypto_algkey}" crypto-alg "${crypto_alg}" udp-src-port 65535 udp-dst-port 65535
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec sa add 100000 spi 200000 crypto-key "${crypto_algkey}" crypto-alg "${crypto_alg}" udp-src-port 65535 udp-dst-port 65535 inbound
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec tunnel protect ipip0 sa-in 100000 sa-out 0
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int unnumbered ipip0 use ${intf}
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state ipip0 up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 192.82.0.1/16 via ipip0
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 192.162.0.0/16 via 10.12.0.2 ${intf}
fi

echo "IPSec configuration successful!"
