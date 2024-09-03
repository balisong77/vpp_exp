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
#include <protocol1/protocol1.h>
#include <vlib/vlib.h>
#include <vnet/pg/pg.h>
#include <vnet/vnet.h>
#include <vppinfra/error.h>
#include <vppinfra/xxhash.h>

// __attribute__((optnone)) static void clib_xxhash1(vlib_buffer_t *b0) {
//   int i;
//   u64 *pos, hash;
//   pos = vlib_buffer_get_current(b0);

// #pragma unroll(CAL_HASH_NUM)
//   for (i = 0; i < CAL_HASH_NUM; i++) {
//     u64 k1, h64;
//     u64 key = *pos;
//     k1 = key;
//     h64 = 0x9e3779b97f4a7c13LL + PRIME64_5 + 8;
//     k1 *= PRIME64_2;
//     k1 = XXH_rotl64(k1, 31);
//     k1 *= PRIME64_1;
//     h64 ^= k1;
//     h64 = XXH_rotl64(h64, 27) * PRIME64_1 + PRIME64_4;

//     h64 ^= h64 >> 33;
//     h64 *= PRIME64_2;
//     h64 ^= h64 >> 29;
//     h64 *= PRIME64_3;
//     h64 ^= h64 >> 32;
//     hash = h64;
//     protocol1_main.temp_vec[i] = hash;
//     pos += 1;
//   }
// }

typedef struct {
  u32 next_index;
  u8 src_ip[4];
  u8 dst_ip[4];
  u16 current_length;
} protocol1_trace_t;

#ifndef CLIB_MARCH_VARIANT
static u8 *my_format_ip_address(u8 *s, va_list *args) {
  u8 *a = va_arg(*args, u8 *);
  return format(s, "%3u.%3u.%3u.%3u", a[0], a[1], a[2], a[3]);
}

/* packet trace format function */
static u8 *format_protocol1_trace(u8 *s, va_list *args) {
  CLIB_UNUSED(vlib_main_t * vm) = va_arg(*args, vlib_main_t *);
  CLIB_UNUSED(vlib_node_t * node) = va_arg(*args, vlib_node_t *);
  protocol1_trace_t *t = va_arg(*args, protocol1_trace_t *);

  s = format(s, "Protocol1: next index %d\n", t->next_index);
  s = format(s, "  src_ip %U -> dst_ip %U", my_format_ip_address, t->src_ip,
             my_format_ip_address, t->dst_ip);
  s = format(s, "  current_length: %d", t->current_length);
  return s;
}

vlib_node_registration_t protocol1_node;

#endif /* CLIB_MARCH_VARIANT */

#define foreach_protocol1_error                                                \
  _(PROCESSED, "protocol1 error processed packets")

typedef enum {
#define _(sym, str) PROTOCOL1_ERROR_##sym,
  foreach_protocol1_error
#undef _
      PROTOCOL1_N_ERROR,
} protocol1_error_t;

#ifndef CLIB_MARCH_VARIANT
static char *protocol1_error_strings[] = {
#define _(sym, string) string,
    foreach_protocol1_error
#undef _
};
#endif /* CLIB_MARCH_VARIANT */

typedef enum {
  PROTOCOL1_NEXT_IP4_LOOKUP,
  PROTOCOL1_NEXT_DROP,
  PROTOCOL1_N_NEXT,
} protocol1_next_t;

VLIB_NODE_FN(protocol1_node)
(vlib_main_t *vm, vlib_node_runtime_t *node, vlib_frame_t *frame) {
  u32 n_left_from, *from, *to_next;
  protocol1_next_t next_index;
  u32 pkts_processed = 0;

  from = vlib_frame_vector_args(frame);
  n_left_from = frame->n_vectors;
  next_index = node->cached_next_index;

  while (n_left_from > 0) {
    u32 n_left_to_next;

    vlib_get_next_frame(vm, node, next_index, to_next, n_left_to_next);

    while (n_left_from >= 4 && n_left_to_next >= 2) {
      u32 next0 = PROTOCOL1_NEXT_IP4_LOOKUP;
      u32 next1 = PROTOCOL1_NEXT_IP4_LOOKUP;
      u32 bi0, bi1;
      vlib_buffer_t *b0, *b1;

      /* Prefetch next iteration. */
      {
        vlib_buffer_t *p2, *p3;

        p2 = vlib_get_buffer(vm, from[2]);
        p3 = vlib_get_buffer(vm, from[3]);

        vlib_prefetch_buffer_header(p2, LOAD);
        vlib_prefetch_buffer_header(p3, LOAD);

        CLIB_PREFETCH(p2->data, CAL_HASH_NUM * HASH_BYTES, STORE);
        CLIB_PREFETCH(p3->data, CAL_HASH_NUM * HASH_BYTES, STORE);
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

      /*check that packet size is grater than hash key size*/
      if (PREDICT_TRUE(b0->current_length >= CAL_HASH_NUM * HASH_BYTES)) {
        int i;
        u64 *pos, hash;
        pos = vlib_buffer_get_current(b0);
        for (i = 0; i < CAL_HASH_NUM; i++) {
          hash = clib_xxhash(*pos);
          protocol1_main.temp_vec[i] = hash;
          pos += 1;
        }
      } else {
        /*drop packet*/
        next0 = PROTOCOL1_NEXT_DROP;
      }

      /*check that packet size is grater than hash key size*/
      if (PREDICT_TRUE(b1->current_length >= CAL_HASH_NUM * HASH_BYTES)) {
        int i;
        u64 *pos, hash;
        pos = vlib_buffer_get_current(b1);
        for (i = 0; i < CAL_HASH_NUM; i++) {
          hash = clib_xxhash(*pos);
          protocol1_main.temp_vec[i] = hash;
          pos += 1;
        }
      } else {
        /*drop packet*/
        next1 = PROTOCOL1_NEXT_DROP;
      }

      pkts_processed += 2;

      if (PREDICT_FALSE((node->flags & VLIB_NODE_FLAG_TRACE))) {
        if (b0->flags & VLIB_BUFFER_IS_TRACED) {
          protocol1_trace_t *t = vlib_add_trace(vm, node, b0, sizeof(*t));
          t->next_index = next0;
          ip4_header_t *ip0 = vlib_buffer_get_current(b0);
          clib_memcpy(t->src_ip, &ip0->src_address, sizeof(t->src_ip));
          clib_memcpy(t->dst_ip, &ip0->dst_address, sizeof(t->dst_ip));
          t->current_length = b0->current_length;
        }
        if (b1->flags & VLIB_BUFFER_IS_TRACED) {
          protocol1_trace_t *t = vlib_add_trace(vm, node, b1, sizeof(*t));
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
      u32 next0 = PROTOCOL1_NEXT_IP4_LOOKUP;

      /* speculatively enqueue b0 to the current next frame */
      bi0 = from[0];
      to_next[0] = bi0;
      from += 1;
      to_next += 1;
      n_left_from -= 1;
      n_left_to_next -= 1;

      b0 = vlib_get_buffer(vm, bi0);
      /*
       * Direct from the driver, we should be at offset 0
       * aka at &b0->data[0]
       */
      if (PREDICT_TRUE(b0->current_length >= CAL_HASH_NUM * HASH_BYTES)) {
        int i;
        u64 *pos, hash;
        pos = vlib_buffer_get_current(b0);
        for (i = 0; i < CAL_HASH_NUM; i++) {
          hash = clib_xxhash(*pos);
          protocol1_main.temp_vec[i] = hash;
          pos += 1;
        }
      } else {
        /*drop packet*/
        next0 = PROTOCOL1_NEXT_DROP;
      }

      pkts_processed += 1;

      if (PREDICT_FALSE((node->flags & VLIB_NODE_FLAG_TRACE))) {
        if (b0->flags & VLIB_BUFFER_IS_TRACED) {
          protocol1_trace_t *t = vlib_add_trace(vm, node, b0, sizeof(*t));
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

  vlib_node_increment_counter(vm, protocol1_node.index,
                              PROTOCOL1_ERROR_PROCESSED, pkts_processed);
  return frame->n_vectors;
}

/* *INDENT-OFF* */
#ifndef CLIB_MARCH_VARIANT
VLIB_REGISTER_NODE(protocol1_node) = {
    .name = "protocol1",
    .vector_size = sizeof(u32),
    .format_trace = format_protocol1_trace,
    .type = VLIB_NODE_TYPE_INTERNAL,

    .n_errors = ARRAY_LEN(protocol1_error_strings),
    .error_strings = protocol1_error_strings,

    .n_next_nodes = PROTOCOL1_N_NEXT,

    /* edit / add dispositions here */
    .next_nodes = {[PROTOCOL1_NEXT_IP4_LOOKUP] = "ip4-lookup",
                   [PROTOCOL1_NEXT_DROP] = "ip4-drop"},
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
