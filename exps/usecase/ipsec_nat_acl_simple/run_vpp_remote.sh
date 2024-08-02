#!/usr/bin/env bash 

# 使用示例：sudo ./run_vpp_remote.sh -c 10,11-12

set -e

# vpp和vppctl的路径(vpp_binary变量)默认在../../tools/check-path.sh中指定
DIR=$(dirname "$0")
DATAPLANE_TOP=${DIR}/../..
source "${DATAPLANE_TOP}"/tools/check-path.sh

# 这里也可以直接修改
export vppctl_binary="/usr/local/bin/vppctl"
export vpp_binary="/usr/local/bin/vpp"

# dpdk绑定的网卡名
Ethernet0="Ethernet0"
Ethernet1="Ethernet1"

# VPP runtime socket目录位置
VPP_RUNTIME_DIR="/run/vpp/remote"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_remote.sock"
VPP_REMOTE_PIDFILE="${VPP_RUNTIME_DIR}/vpp_remote.pid"

# 网卡PCIE设置,数组分别是Ethernet0和Ethernet1的PCIE地址
pcie_addr=("0000:84:00.0" "0000:84:00.1")

# IPSec Config
crypto_alg="aes-gcm-128"
crypto_algkey="4a506a794f574265564551694d653768"
crypto_engine="native"

# 注意，这里rx queue数量默认等于workker线程数量（通过cal_cores函数计算出queues_count变量，在启动VPP时的配置中指定）

help_func()
{
    echo "Usage: ./run_vpp_remote.sh options"
    echo
    echo "Options:"
    echo "  -c <core list>       set CPU affinity. Assign VPP main thread to 1st core"
    echo "                       in list and place worker threads on other listed cores."
    echo "                       Cores are separated by commas, and worker cores can include ranges."
    echo
    echo "Example:"
    echo "  ./run_vpp_remote.sh -c 1,2-3"
    echo
}

err_cleanup()
{
    echo "Remote VPP setup error, cleaning up..."
    if [[ -f "${VPP_REMOTE_PIDFILE}" ]]; then
        vpp_remote_pid=$(cat "${VPP_REMOTE_PIDFILE}")
        sudo kill -9 "${vpp_remote_pid}"
        sudo rm "${VPP_REMOTE_PIDFILE}"
    fi
    exit 1
}
cal_cores()
{
  IFS=',' read -ra array <<< "$1"
  count=0

  for item in "${array[@]}"; do
      if [[ $item == *-* ]]; then
          start=${item%-*}
          end=${item#*-}
          count=$((count + end - start + 1))
      else
          count=$((count + 1))
      fi
  done

  echo $count
}
setup_iface()
{
    # 网卡设置
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state "${Ethernet0}" up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ip address "${Ethernet0}" 10.12.0.5/16
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state "${Ethernet1}" up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ip address "${Ethernet1}" 192.82.0.5/16

    # 检查网卡是否启动成功
    LOG=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show interface)
    if [[ "${LOG}" == *"${Ethernet0}"* && "${LOG}" == *"${Ethernet1}"* ]]; then
        echo "Successfully set up interfaces!"
    else
        echo "Failed to set up interfaces!"
        err_cleanup
    fi

    # IPSec 配置
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set crypto handler all "${crypto_engine}"
    sudo "${vppctl_binary}" -s "${SOCKFILE}" create loopback interface
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state loop0 up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int ip addr loop0 192.162.0.1/32
    sudo "${vppctl_binary}" -s "${SOCKFILE}" create ipip tunnel src 192.162.0.1 dst 192.161.0.1
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec sa add 100000 spi 200000 crypto-key "${crypto_algkey}" crypto-alg "${crypto_alg}" udp-src-port 65535 udp-dst-port 65535
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec sa add 0 spi 100000 crypto-key "${crypto_algkey}" crypto-alg "${crypto_alg}" udp-src-port 65535 udp-dst-port 65535 inbound
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ipsec tunnel protect ipip0 sa-in 0 sa-out 100000
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int unnumbered ipip0 use ${Ethernet0}
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int state ipip0 up
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 192.161.0.0/16 via 10.12.0.3 ${Ethernet0}
    # 借助 192.82.0.100 这个虚拟下一跳IP(Trex收包port的IP)，配置路由表
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set ip neighbor "${Ethernet1}" 192.82.0.100 04:3f:72:f4:40:4a
    # 将IPSec流量转回node3 Trex
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 192.82.0.1/32 via 192.82.0.100 "${Ethernet1}"
    # 将L3 fwd流量转回node3 Trex
    sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 192.82.0.2/32 via 192.82.0.100 "${Ethernet1}"
    echo "IPSec configuration successful!"

    # NAT配置
    sudo "${vppctl_binary}" -s "${SOCKFILE}" nat44 plugin enable
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set int nat44 out ipip0 in "${Ethernet1}"
    sudo "${vppctl_binary}" -s "${SOCKFILE}" nat44 add address 10.12.0.10 
    sudo "${vppctl_binary}" -s "${SOCKFILE}" nat44 add static mapping local 192.82.0.1 external 10.12.0.10
    sudo "${vppctl_binary}" -s "${SOCKFILE}" nat44 forwarding enable
    echo "DNAT configuration successful!"

    # ACL配置
    sudo "${vppctl_binary}" -s "${SOCKFILE}" classify table acl-miss-next deny mask l3 ip4 dst buckets 1000
    sudo "${vppctl_binary}" -s "${SOCKFILE}" classify session acl-hit-next permit table-index 0 match l3 ip4 dst 192.162.0.1
    sudo "${vppctl_binary}" -s "${SOCKFILE}" classify session acl-hit-next permit table-index 0 match l3 ip4 dst 192.82.0.2  
    sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface input acl intfc "${Ethernet0}" ip4-table 0
    echo "ACL configuration successful!"
}

options=(-o "h:c:")
opts=$(getopt "${options[@]}" -- "$@")
eval set -- "$opts"

while true; do
    case "$1" in
      -h)
          help_func
          exit 0
          ;;
      -c)
          if ! [[ "$2" =~ ^[0-9]{1,3}((,[0-9]{1,3})|(,[0-9]{1,3}-[0-9]{1,3}))+$ ]]; then
              echo "error: \"-c\" requires correct cpu isolation core id"
              help_func
              exit 1
          fi
          main_core=$(echo "$2" | cut -d "," -f 1)
          worker_core=$(echo "$2" | cut -d "," -f 2-)
          if [[ "${main_core}" == "${worker_core}" ]]; then
              echo "error: \"-c\" option bad usage"
              help_func
              exit 1
          fi
          queues_count=$(cal_cores "$worker_core")
        #   queues_count=1
          echo "queues_count: ""${queues_count}"
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

if ! [[ "${main_core}" && "${worker_core}" ]]; then
    echo "require an option: \"-c\""
    help_func
    exit 1
fi

check_vpp
check_vppctl

# 启动VPP
sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_REMOTE_PIDFILE} }"                                                              \
                        cpu "{ main-core ${main_core} corelist-workers ${worker_core} }"                                                                                            \
                        plugins "{ plugin default { disable } plugin dpdk_plugin.so { enable } plugin crypto_native_plugin.so {enable} plugin crypto_openssl_plugin.so {enable} plugin ping_plugin.so { enable } plugin nat_plugin.so {enable}}"  \
                        dpdk "{ dev ${pcie_addr[0]} { name "${Ethernet0}" num-tx-queues ${queues_count} num-rx-queues ${queues_count}} 
                                dev ${pcie_addr[1]} { name "${Ethernet1}" num-tx-queues ${queues_count} num-rx-queues ${queues_count}}}"

echo "Remote VPP starting up"


sleep 0.5

# 尝试连接vppctl socket
set +e
max_conn_retries=10
for conn_count in $(seq ${max_conn_retries}); do
    if ! output=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show threads); then
        if [[ ${conn_count} -eq ${max_conn_retries} ]]; then
            err_cleanup
        fi
        sleep 0.5
    elif [[ -z "${output}" ]]; then
        err_cleanup
    else
        break
    fi
done
set -e

echo "Setting up DPDK interfaces..."

# 网卡设置 + IPsec配置
setup_iface

echo "Successfully start remote VPP instance!"
