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

# VPP runtime socket目录位置
VPP_RUNTIME_DIR="/run/vpp/remote"
SOCKFILE="${VPP_RUNTIME_DIR}/cli_remote.sock"
VPP_REMOTE_PIDFILE="${VPP_RUNTIME_DIR}/vpp_remote.pid"

# 网卡PCIE设置,数组分别是 ens2f0v0 到 ens2f0v9 的PCIE地址
pcie_addr=("0000:84:02.3" "0000:84:02.4" "0000:84:02.5" "0000:84:02.6" "0000:84:02.7" "0000:84:03.0" "0000:84:03.1" "0000:84:03.2" "0000:84:03.3" "0000:84:03.4")
Ethernet_name=("Ethernet0" "Ethernet1" "Ethernet2" "Ethernet3" "Ethernet4" "Ethernet5" "Ethernet6" "Ethernet7" "Ethernet8" "Ethernet9")

# 流量从Trex的 ens2f0v0 发往 ens5f1v0，然后通过VPP处理后再发回 ens2f0v0，后续网卡也同样一一对应
# Node3 Trex端接收网卡 ens2f0v0 到 ens2f0v9 的MAC地址
dst_mac_addr=("76:86:f5:9d:a5:58" "a6:70:d3:c8:98:a8" "9a:9e:ab:f4:d0:65" "b6:ec:2e:92:eb:99" "7e:5d:f6:eb:54:8f" "c6:9f:0c:61:96:1b" "ca:4d:4f:92:24:1c" "a6:5b:9c:53:25:29" "b2:d6:3e:bc:0d:08" "96:7c:75:08:ca:93")

# Node5 VPP端接收网卡 ens5f1v0 到 ens5f1v9 的MAC地址
# src_mac_addr=("1a:9f:8d:63:f8:74" "d6:b1:ce:10:22:4a" "5e:80:06:54:2e:e1" "82:b6:63:52:58:26" "ba:34:52:80:9d:2b" "9e:1e:e0:8e:2b:36" "42:02:24:0f:05:07" "f6:91:a2:79:92:02" "82:05:c6:54:b5:9c" "86:3d:54:b9:79:a7")

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

# 注意，这里rx queue数量默认等于workker线程数量（通过cal_cores函数计算出queues_count变量，在启动VPP时的配置中指定）
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
    for ((index=0; index<worker_count; index++)); do
        EthernetX="${Ethernet_name[$index]}"
        # Your code here using $var and $index
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface state "${EthernetX}" up
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface ip address "${EthernetX}" 192.168.1.$((index+1))/32
        # 借助 192.168.1.100 这个虚拟下一跳IP(Trex收包port的IP)，配置路由表
        sudo "${vppctl_binary}" -s "${SOCKFILE}" set ip neighbor "${EthernetX}" 192.168.2.$((index+1)) ${dst_mac_addr[$index]}
        # 将IPv4 L3 fwd流量转回node3 Trex
        sudo "${vppctl_binary}" -s "${SOCKFILE}" ip route add 192.168.3.$((index+1))/32 via 192.168.2.$((index+1)) "${EthernetX}"
        # pin_core时，将每个网卡的所有队列绑定到同一个worker线程
        if [[ pin_core -eq 1 ]]; then
            for ((queue=0; queue<queues_count; queue++)); do
                sudo "${vppctl_binary}" -s "${SOCKFILE}" set interface rx-placement "${EthernetX}" queue "${queue}" worker "${index}"
            done
        fi
    done

    # 检查网卡是否启动成功
    LOG=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show interface)
    if [[ "${LOG}" == *"${Ethernet0}"* && "${LOG}" == *"${Ethernet1}"* ]]; then
        echo "Successfully set up interfaces!"
    else
        echo "Failed to set up interfaces!"
        err_cleanup
    fi

    echo "ALL NIC IPv4 L3 fwd configuration successful!"
}

options=(-o "h:c:p")
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
          shift 2
          ;;
      -p)
          pin_core=1
          shift 1
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

# 计算worker线程数量
worker_count=$(cal_cores "$worker_core")

# pin_core时，每个网卡只设置一个队列
# all_core时，每个网卡设置与worker_core数量相同的队列
if [[ pin_core -eq 1 ]]; then
    # queues_count=1
    queues_count=${worker_count}
else
    queues_count=${worker_count}
fi
echo "queues_count: ""${queues_count}"


if ! [[ "${main_core}" && "${worker_core}" ]]; then
    echo "require an option: \"-c\""
    help_func
    exit 1
fi

check_vpp
check_vppctl

# 拼接VPP启动命令，DPDK绑定网卡的数量与worker线程数量相同
vpp_start_cmd="sudo ${vpp_binary} unix { runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_REMOTE_PIDFILE} }
                    cpu { main-core ${main_core} corelist-workers ${worker_core} }
                    plugins { plugin default { enable } plugin dpdk_plugin.so { enable } plugin crypto_native_plugin.so {enable} plugin crypto_openssl_plugin.so {enable} plugin ping_plugin.so { enable } plugin nat_plugin.so {enable} plugin test_batch.so {enable} }
                    dpdk { "
for ((index=0; index<worker_count; index++)); do
    vpp_start_cmd+="dev ${pcie_addr[$index]} { name ${Ethernet_name[$index]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}} "
done
vpp_start_cmd+="}"

# 执行拼接好的VPP启动命令
eval $vpp_start_cmd

# sudo "${vpp_binary}" unix "{ runtime-dir ${VPP_RUNTIME_DIR} cli-listen ${SOCKFILE} pidfile ${VPP_REMOTE_PIDFILE} }"                                                              \
#                         cpu "{ main-core ${main_core} corelist-workers ${worker_core} }"                                                                                            \
#                         plugins "{ plugin default { enable } plugin dpdk_plugin.so { enable } plugin crypto_native_plugin.so {enable} plugin crypto_openssl_plugin.so {enable} plugin ping_plugin.so { enable } plugin nat_plugin.so {enable} plugin test_batch.so {enable}}"  \
#                         dpdk "{ dev ${pcie_addr[0]} { name ${Ethernet_name[0]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}} 
#                                 dev ${pcie_addr[1]} { name ${Ethernet_name[1]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}}
#                                 dev ${pcie_addr[2]} { name ${Ethernet_name[2]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}}
#                                 dev ${pcie_addr[3]} { name ${Ethernet_name[3]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}}
#                                 dev ${pcie_addr[4]} { name ${Ethernet_name[4]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}}
#                                 dev ${pcie_addr[5]} { name ${Ethernet_name[5]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}}
#                                 dev ${pcie_addr[6]} { name ${Ethernet_name[6]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}}
#                                 dev ${pcie_addr[7]} { name ${Ethernet_name[7]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}}
#                                 dev ${pcie_addr[8]} { name ${Ethernet_name[8]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}}
#                                 dev ${pcie_addr[9]} { name ${Ethernet_name[9]} num-tx-queues ${queues_count} num-rx-queues ${queues_count}}}"

echo "Remote VPP starting up"


sleep 0.5

# 尝试连接vppctl socket
set +e
max_conn_retries=30
for conn_count in $(seq ${max_conn_retries}); do
    if ! output=$(sudo "${vppctl_binary}" -s "${SOCKFILE}" show threads); then
        if [[ ${conn_count} -eq ${max_conn_retries} ]]; then
            err_cleanup
        fi
        sleep 1
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

echo "All NIC Successfully start remote VPP instance!"
