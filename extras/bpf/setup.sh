#!/bin/bash
sudo vppctl -s  /run/vpp/rt/cli_rt.sock 'create interface af_xdp host-if ens5f0np0 num-rx-queues all prog /mnt/disk1/zhaolunqi/vpp/extras/bpf/af_xdp.bpf.o'

sudo vppctl -s  /run/vpp/rt/cli_rt.sock 'set int ip addr ens5f0np0/0 192.168.230.105/32'

sudo vppctl -s  /run/vpp/rt/cli_rt.sock 'set int mac address ens5f0np0/0 04:3f:72:f4:41:16'

sudo vppctl -s  /run/vpp/rt/cli_rt.sock 'set int mtu packet 3000 ens5f0np0/0'

sudo vppctl -s  /run/vpp/rt/cli_rt.sock 'set int state ens5f0np0/0 up'

sudo vppctl -s  /run/vpp/rt/cli_rt.sock 'trace add af_xdp-input 10'