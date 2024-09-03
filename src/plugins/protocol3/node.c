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
#include <protocol3/protocol3.h>
#include <vlib/vlib.h>
#include <vnet/pg/pg.h>
#include <vnet/vnet.h>
#include <vppinfra/error.h>
#include <vppinfra/xxhash.h>
#include "../protocol_node_fn.h"

typedef struct {
  u32 next_index;
  u8 src_ip[4];
  u8 dst_ip[4];
  u16 current_length;
} protocol3_trace_t;

#ifndef CLIB_MARCH_VARIANT
static u8 *my_format_ip_address(u8 *s, va_list *args) {
  u8 *a = va_arg(*args, u8 *);
  return format(s, "%3u.%3u.%3u.%3u", a[0], a[1], a[2], a[3]);
}

/* packet trace format function */
static u8 *format_protocol3_trace(u8 *s, va_list *args) {
  CLIB_UNUSED(vlib_main_t * vm) = va_arg(*args, vlib_main_t *);
  CLIB_UNUSED(vlib_node_t * node) = va_arg(*args, vlib_node_t *);
  protocol3_trace_t *t = va_arg(*args, protocol3_trace_t *);

  s = format(s, "protocol3: next index %d\n", t->next_index);
  s = format(s, "  src_ip %U -> dst_ip %U", my_format_ip_address, t->src_ip,
             my_format_ip_address, t->dst_ip);
  s = format(s, "  current_length: %d", t->current_length);
  return s;
}

vlib_node_registration_t protocol3_node;

#endif /* CLIB_MARCH_VARIANT */

#define foreach_protocol3_error                                                \
  _(PROCESSED, "protocol3 error processed packets")

typedef enum {
#define _(sym, str) PROTOCOL3_ERROR_##sym,
  foreach_protocol3_error
#undef _
      PROTOCOL3_N_ERROR,
} protocol3_error_t;

#ifndef CLIB_MARCH_VARIANT
static char *protocol3_error_strings[] = {
#define _(sym, string) string,
    foreach_protocol3_error
#undef _
};
#endif /* CLIB_MARCH_VARIANT */

typedef enum {
  CHAIN_NEXT_NODE,
  PROTOCOL3_N_NEXT,
} protocol3_next_t;

VLIB_NODE_FN(protocol3_node)
(vlib_main_t *vm, vlib_node_runtime_t *node, vlib_frame_t *frame) {
  u32 n_left_from, *from, *to_next;
  protocol3_next_t next_index;
  u32 pkts_processed = 0;

  from = vlib_frame_vector_args(frame);
  n_left_from = frame->n_vectors;
  next_index = node->cached_next_index;

  while (n_left_from > 0) {
    u32 n_left_to_next;

    vlib_get_next_frame(vm, node, next_index, to_next, n_left_to_next);

    while (n_left_from >= 4 && n_left_to_next >= 2) {
      u32 next0 = CHAIN_NEXT_NODE;
      u32 next1 = CHAIN_NEXT_NODE;
      u32 bi0, bi1;
      vlib_buffer_t *b0, *b1;

      /* Prefetch next iteration. */
      {
        vlib_buffer_t *p2, *p3;

        p2 = vlib_get_buffer(vm, from[2]);
        p3 = vlib_get_buffer(vm, from[3]);

        vlib_prefetch_buffer_header(p2, LOAD);
        vlib_prefetch_buffer_header(p3, LOAD);

        CLIB_PREFETCH(p2->data, CLIB_CACHE_LINE_BYTES, STORE);
        CLIB_PREFETCH(p3->data, CLIB_CACHE_LINE_BYTES, STORE);
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

      // 使用宏定义的函数处理数据包
      DUAL_PKT_PROCESS_FN(protocol3);

      pkts_processed += 2;

      if (PREDICT_FALSE((node->flags & VLIB_NODE_FLAG_TRACE))) {
        if (b0->flags & VLIB_BUFFER_IS_TRACED) {
          protocol3_trace_t *t = vlib_add_trace(vm, node, b0, sizeof(*t));
          t->next_index = next0;
          ip4_header_t *ip0 = vlib_buffer_get_current(b0);
          clib_memcpy(t->src_ip, &ip0->src_address, sizeof(t->src_ip));
          clib_memcpy(t->dst_ip, &ip0->dst_address, sizeof(t->dst_ip));
          t->current_length = b0->current_length;
        }
        if (b1->flags & VLIB_BUFFER_IS_TRACED) {
          protocol3_trace_t *t = vlib_add_trace(vm, node, b1, sizeof(*t));
          t->next_index = next1;
          ip4_header_t *ip1 = vlib_buffer_get_current(b1);
          clib_memcpy(t->src_ip, &ip1->src_address, sizeof(t->src_ip));
          clib_memcpy(t->dst_ip, &ip1->dst_address, sizeof(t->dst_ip));
          t->current_length = b0->current_length;
        }
      }

      /* verify speculative enqueues, maybe switch current next frame */
      vlib_validate_buffer_enqueue_x2(vm, node, next_index, to_next,
                                      n_left_to_next, bi0, bi1, next0, next1);
    }

    while (n_left_from > 0 && n_left_to_next > 0) {
      u32 bi0;
      vlib_buffer_t *b0;
      u32 next0 = CHAIN_NEXT_NODE;

      /* speculatively enqueue b0 to the current next frame */
      bi0 = from[0];
      to_next[0] = bi0;
      from += 1;
      to_next += 1;
      n_left_from -= 1;
      n_left_to_next -= 1;

      b0 = vlib_get_buffer(vm, bi0);

      // 使用宏定义的函数处理数据包
      SINGLE_PKT_PROCESS_FN(protocol3);

      pkts_processed += 1;

      if (PREDICT_FALSE((node->flags & VLIB_NODE_FLAG_TRACE))) {
        if (b0->flags & VLIB_BUFFER_IS_TRACED) {
          protocol3_trace_t *t = vlib_add_trace(vm, node, b0, sizeof(*t));
          t->next_index = next0;
          ip4_header_t *ip0 = vlib_buffer_get_current(b0);
          clib_memcpy(t->src_ip, &ip0->src_address, sizeof(t->src_ip));
          clib_memcpy(t->dst_ip, &ip0->dst_address, sizeof(t->dst_ip));
          t->current_length = b0->current_length;
        }
      }

      /* verify speculative enqueue, maybe switch current next frame */
      vlib_validate_buffer_enqueue_x1(vm, node, next_index, to_next,
                                      n_left_to_next, bi0, next0);
    }

    vlib_put_next_frame(vm, node, next_index, n_left_to_next);
  }

  vlib_node_increment_counter(vm, protocol3_node.index,
                              PROTOCOL3_ERROR_PROCESSED, pkts_processed);
  return frame->n_vectors;
}

/* *INDENT-OFF* */
#ifndef CLIB_MARCH_VARIANT
VLIB_REGISTER_NODE(protocol3_node) = {
    .name = "protocol3",
    .vector_size = sizeof(u32),
    .format_trace = format_protocol3_trace,
    .type = VLIB_NODE_TYPE_INTERNAL,

    .n_errors = ARRAY_LEN(protocol3_error_strings),
    .error_strings = protocol3_error_strings,

    .n_next_nodes = PROTOCOL3_N_NEXT,

    /* edit / add dispositions here */
    .next_nodes = {[CHAIN_NEXT_NODE] = "protocol3_2"},
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
