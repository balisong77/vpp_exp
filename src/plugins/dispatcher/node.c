/*
 * node.c - skeleton vpp engine plug-in dual-loop node skeleton
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
#include <dispatcher/dispatcher.h>
#include <vlib/vlib.h>
#include <vnet/pg/pg.h>
#include <vnet/vnet.h>
#include <vppinfra/error.h>

typedef struct {
  u32 next_index;
  u8 src_ip[4];
  u8 dst_ip[4];
} dispatcher_trace_t;

#ifndef CLIB_MARCH_VARIANT
static u8 *my_format_ip_address(u8 *s, va_list *args) {
  u8 *a = va_arg(*args, u8 *);
  return format(s, "%02x.%02x.%02x.%02x", a[0], a[1], a[2], a[3]);
}

/* packet trace format function */
static u8 *format_dispatcher_trace(u8 *s, va_list *args) {
  CLIB_UNUSED(vlib_main_t * vm) = va_arg(*args, vlib_main_t *);
  CLIB_UNUSED(vlib_node_t * node) = va_arg(*args, vlib_node_t *);
  dispatcher_trace_t *t = va_arg(*args, dispatcher_trace_t *);

  s = format(s, "DISPATCHER: next index %d\n", t->next_index);
  s = format(s, "  src_ip %U -> dst_ip %U", my_format_ip_address, t->src_ip,
             my_format_ip_address, t->dst_ip);
  return s;
}

vlib_node_registration_t dispatcher_node;

#endif /* CLIB_MARCH_VARIANT */

#define foreach_dispatcher_error _(DISPATCHED, "Dispatcher packets processed")

typedef enum {
#define _(sym, str) DISPATCHER_ERROR_##sym,
  foreach_dispatcher_error
#undef _
      DISPATCHER_N_ERROR,
} dispatcher_error_t;

#ifndef CLIB_MARCH_VARIANT
static char *dispatcher_error_strings[] = {
#define _(sym, string) string,
    foreach_dispatcher_error
#undef _
};
#endif /* CLIB_MARCH_VARIANT */

typedef enum {
  DISPATCHER_NEXT_PROTOCOL_1,
  DISPATCHER_NEXT_PROTOCOL_2,
  DISPATCHER_NEXT_PROTOCOL_3,
  DISPATCHER_NEXT_PROTOCOL_4,
  DISPATCHER_NEXT_DROP,
  DISPATCHER_N_NEXT,
} dispatcher_next_t;

#define foreach_mac_address_offset                                             \
  _(0)                                                                         \
  _(1)                                                                         \
  _(2)                                                                         \
  _(3)                                                                         \
  _(4)                                                                         \
  _(5)

VLIB_NODE_FN(dispatcher_node)
(vlib_main_t *vm, vlib_node_runtime_t *node, vlib_frame_t *frame) {
  u32 n_left_from, *from, *to_next;
  dispatcher_next_t next_index;

  // 记录分流的包的数量
  u32 pkts_dispatched = 0;

  from = vlib_frame_vector_args(frame);
  n_left_from = frame->n_vectors;
  next_index = node->cached_next_index;

  while (n_left_from > 0) {
    u32 n_left_to_next;

    vlib_get_next_frame(vm, node, next_index, to_next, n_left_to_next);

    while (n_left_from >= 4 && n_left_to_next >= 2) {
      u32 next0 = DISPATCHER_NEXT_PROTOCOL_1;
      u32 next1 = DISPATCHER_NEXT_PROTOCOL_1;
      u32 bi0, bi1;
      vlib_buffer_t *b0, *b1;
      // ip 报头指针
      ip4_header_t *ip0, *ip1;

      /* Prefetch next iteration. */
      {
        vlib_buffer_t *p2, *p3;

        p2 = vlib_get_buffer(vm, from[2]);
        p3 = vlib_get_buffer(vm, from[3]);

        vlib_prefetch_buffer_header(p2, LOAD);
        vlib_prefetch_buffer_header(p3, LOAD);

        CLIB_PREFETCH(p2->data, sizeof(ip0[0]), LOAD);
        CLIB_PREFETCH(p3->data, sizeof(ip0[0]), LOAD);
      }

      /* speculatively enqueue b0 and b1 to the current next frame */
      to_next[0] = bi0 = from[0];
      to_next[1] = bi1 = from[1];
      from += 2;
      to_next += 2;
      n_left_from -= 2;
      n_left_to_next -= 2;

      b0 = vlib_get_buffer(vm, bi0);
      b1 = vlib_get_buffer(vm, bi1);

      // 获取ip报文头
      ip0 = vlib_buffer_get_current(b0);
      ip1 = vlib_buffer_get_current(b1);

      switch (ip0->address_pair.src.as_u8[0]) {
      case 1:
        next0 = DISPATCHER_NEXT_PROTOCOL_1;
        break;
      case 2:
        next0 = DISPATCHER_NEXT_PROTOCOL_2;
        break;
      case 3:
        next0 = DISPATCHER_NEXT_PROTOCOL_3;
        break;
      case 4:
        next0 = DISPATCHER_NEXT_PROTOCOL_4;
        break;
      default:
        next0 = DISPATCHER_NEXT_DROP;
        break;
      }

      switch (ip1->address_pair.src.as_u8[0]) {
      case 1:
        next1 = DISPATCHER_NEXT_PROTOCOL_1;
        break;
      case 2:
        next1 = DISPATCHER_NEXT_PROTOCOL_2;
        break;
      case 3:
        next1 = DISPATCHER_NEXT_PROTOCOL_3;
        break;
      case 4:
        next1 = DISPATCHER_NEXT_PROTOCOL_4;
        break;
      default:
        next1 = DISPATCHER_NEXT_DROP;
        break;
      }

      pkts_dispatched += 2;

      if (PREDICT_FALSE((node->flags & VLIB_NODE_FLAG_TRACE))) {
        if (b0->flags & VLIB_BUFFER_IS_TRACED) {
          dispatcher_trace_t *t = vlib_add_trace(vm, node, b0, sizeof(*t));
          t->next_index = next0;
          clib_memcpy(t->src_ip, &ip0->src_address, sizeof(t->src_ip));
          clib_memcpy(t->dst_ip, &ip0->dst_address, sizeof(t->dst_ip));
        }
        if (b1->flags & VLIB_BUFFER_IS_TRACED) {
          dispatcher_trace_t *t = vlib_add_trace(vm, node, b1, sizeof(*t));
          t->next_index = next1;
          clib_memcpy(t->src_ip, &ip1->src_address, sizeof(t->src_ip));
          clib_memcpy(t->dst_ip, &ip1->dst_address, sizeof(t->dst_ip));
        }
      }

      /* verify speculative enqueues, maybe switch current next frame */
      vlib_validate_buffer_enqueue_x2(vm, node, next_index, to_next,
                                      n_left_to_next, bi0, bi1, next0, next1);
    }

    while (n_left_from > 0 && n_left_to_next > 0) {
      u32 bi0;
      vlib_buffer_t *b0;
      u32 next0 = DISPATCHER_NEXT_PROTOCOL_1;
      // ip 报头指针
      ip4_header_t *ip0;

      /* speculatively enqueue b0 to the current next frame */
      bi0 = from[0];
      to_next[0] = bi0;
      from += 1;
      to_next += 1;
      n_left_from -= 1;
      n_left_to_next -= 1;

      b0 = vlib_get_buffer(vm, bi0);

      // 获取ip报文头
      ip0 = vlib_buffer_get_current(b0);

      switch (ip0->address_pair.src.as_u8[0]) {
      case 1:
        next0 = DISPATCHER_NEXT_PROTOCOL_1;
        break;
      case 2:
        next0 = DISPATCHER_NEXT_PROTOCOL_2;
        break;
      case 3:
        next0 = DISPATCHER_NEXT_PROTOCOL_3;
        break;
      case 4:
        next0 = DISPATCHER_NEXT_PROTOCOL_4;
        break;
      default:
        next0 = DISPATCHER_NEXT_DROP;
        break;
      }

      pkts_dispatched += 1;

      if (PREDICT_FALSE((node->flags & VLIB_NODE_FLAG_TRACE) &&
                        (b0->flags & VLIB_BUFFER_IS_TRACED))) {
        dispatcher_trace_t *t = vlib_add_trace(vm, node, b0, sizeof(*t));
        t->next_index = next0;
        clib_memcpy(t->src_ip, &ip0->src_address, sizeof(t->src_ip));
        clib_memcpy(t->dst_ip, &ip0->dst_address, sizeof(t->dst_ip));
      }

      /* verify speculative enqueue, maybe switch current next frame */
      vlib_validate_buffer_enqueue_x1(vm, node, next_index, to_next,
                                      n_left_to_next, bi0, next0);
    }

    vlib_put_next_frame(vm, node, next_index, n_left_to_next);
  }

  vlib_node_increment_counter(vm, dispatcher_node.index,
                              DISPATCHER_ERROR_DISPATCHED, pkts_dispatched);
  return frame->n_vectors;
}

/* *INDENT-OFF* */
#ifndef CLIB_MARCH_VARIANT
VLIB_REGISTER_NODE(dispatcher_node) = {
    .name = "dispatcher",
    .vector_size = sizeof(u32),
    .format_trace = format_dispatcher_trace,
    .type = VLIB_NODE_TYPE_INTERNAL,

    .n_errors = ARRAY_LEN(dispatcher_error_strings),
    .error_strings = dispatcher_error_strings,

    .n_next_nodes = DISPATCHER_N_NEXT,

    /* edit / add dispositions here */
    .next_nodes = {[DISPATCHER_NEXT_PROTOCOL_1] = "protocol1",
                   [DISPATCHER_NEXT_PROTOCOL_2] = "protocol2",
                   [DISPATCHER_NEXT_PROTOCOL_3] = "protocol3",
                   [DISPATCHER_NEXT_PROTOCOL_4] = "protocol4",
                   [DISPATCHER_NEXT_DROP] = "ip4-drop"},
};
#endif /* CLIB_MARCH_VARIANT */
/* *INDENT-ON* */
/*
 * fd.io coding-style-patch-verification: ON
 *
 * Local Variables:
 * eval: (c-set-style "gnu")
 * End:
 */
