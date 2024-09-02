
/*
 * protocol2.h - skeleton vpp engine plug-in header file
 *
 * Copyright (c) <current-year> <your-organization>
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at:
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#ifndef __included_protocol2_h__
#define __included_protocol2_h__

#include <vnet/vnet.h>
#include <vnet/ip/ip.h>
#include <vnet/ethernet/ethernet.h>

#include <vppinfra/hash.h>
#include <vppinfra/error.h>

#define CAL_HASH_NUM 150
#define HASH_BYTES 8

typedef struct {
    /* API message ID base */
    u16 msg_id_base;

    /* on/off switch for the periodic function */
    u8 periodic_timer_enabled;
    /* Node index, non-zero if the periodic process has been created */
    u32 periodic_node_index;

    // 暂存哈希结果，避免编译优化掉哈希操作
    u64* temp_vec;

    /* convenience */
    vlib_main_t * vlib_main;
    vnet_main_t * vnet_main;
    ethernet_main_t * ethernet_main;
} protocol2_main_t;

extern protocol2_main_t protocol2_main;

extern vlib_node_registration_t protocol2_node;
extern vlib_node_registration_t protocol2_periodic_node;

/* Periodic function events */
#define PROTOCOL2_EVENT1 1
#define PROTOCOL2_EVENT2 2
#define PROTOCOL2_EVENT_PERIODIC_ENABLE_DISABLE 3

void protocol2_create_periodic_process (protocol2_main_t *);

#endif /* __included_protocol2_h__ */

/*
 * fd.io coding-style-patch-verification: ON
 *
 * Local Variables:
 * eval: (c-set-style "gnu")
 * End:
 */

