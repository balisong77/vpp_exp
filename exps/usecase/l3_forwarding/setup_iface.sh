#!/usr/bin/env bash
# 通过memif创建的默认interface名字默认就是Ethernet0和Ethernet1
Ethernet0="Ethernet0"
Ethernet1="Ethernet1"
vppctl_binary="/usr/local/bin/vppctl"
flows_num=1
VPP_RUNTIME_DIR="/run/vpp/rt"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_rt.sock"
MEMIF_SOCKET1="/tmp/memif_dut_1"
MEMIF_SOCKET2="/tmp/memif_dut_2"

sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state "${Ethernet0}" up
sudo "${vppctl_binary}" -s "${SOCKFILE}" set int ip address "${Ethernet0}" 192.168.230.105/24
sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state "${Ethernet1}" up
sudo "${vppctl_binary}" -s "${SOCKFILE}" set int ip address "${Ethernet1}" 192.168.230.115/24
sudo "${vppctl_binary}" -s "${SOCKFILE}" set ip neighbor "${Ethernet1}" 192.168.230.113 04:3f:72:f4:40:4b
sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 1.0.0.1/32 count "${flows_num}" via 192.168.230.113 "${Ethernet1}"

LOG=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show interface)
echo "show int result:""${LOG}"
if ! [[ "${LOG}" == *"${Ethernet0}"* && "${LOG}" == *"${Ethernet1}"* ]]; then
        echo "Failed to set up interfaces!"
        err_cleanup
fi
