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


#include <vlib/vlib.h>
#include <vnet/vnet.h>
#include <vnet/pg/pg.h>
#include <vppinfra/error.h>
#include <test_batch/test_batch.h>
#include <vppinfra/xxhash.h>

typedef struct 
{
  u32 next_index;
  u32 sw_if_index;
  u8 new_src_mac[6];
  u8 new_dst_mac[6];
} test_batch_trace_t;

#ifndef CLIB_MARCH_VARIANT
static u8 *
my_format_mac_address (u8 * s, va_list * args)
{
  u8 *a = va_arg (*args, u8 *);
  return format (s, "%02x:%02x:%02x:%02x:%02x:%02x",
		 a[0], a[1], a[2], a[3], a[4], a[5]);
}

/* packet trace format function */
static u8 * format_test_batch_trace (u8 * s, va_list * args)
{
  CLIB_UNUSED (vlib_main_t * vm) = va_arg (*args, vlib_main_t *);
  CLIB_UNUSED (vlib_node_t * node) = va_arg (*args, vlib_node_t *);
  test_batch_trace_t * t = va_arg (*args, test_batch_trace_t *);
  
  s = format (s, "TEST_BATCH: sw_if_index %d, next index %d\n",
              t->sw_if_index, t->next_index);
  s = format (s, "  new src %U -> new dst %U",
              my_format_mac_address, t->new_src_mac, 
              my_format_mac_address, t->new_dst_mac);
  return s;
}

vlib_node_registration_t test_batch_node;

#endif /* CLIB_MARCH_VARIANT */

#define foreach_test_batch_error \
_(HASHED, "HASH packets processed")

typedef enum {
#define _(sym,str) TEST_BATCH_ERROR_##sym,
  foreach_test_batch_error
#undef _
  TEST_BATCH_N_ERROR,
} test_batch_error_t;

#ifndef CLIB_MARCH_VARIANT
static char * test_batch_error_strings[] = 
{
#define _(sym,string) string,
  foreach_test_batch_error
#undef _
};
#endif /* CLIB_MARCH_VARIANT */

typedef enum 
{
  TEST_BATCH_NEXT_IP4_LOOKUP,
  TEST_BATCH_NEXT_DROP,
  TEST_BATCH_N_NEXT,
} test_batch_next_t;

#define foreach_mac_address_offset              \
_(0)                                            \
_(1)                                            \
_(2)                                            \
_(3)                                            \
_(4)                                            \
_(5)


VLIB_NODE_FN (test_batch_node) (vlib_main_t * vm,
		  vlib_node_runtime_t * node,
		  vlib_frame_t * frame)
{
  u32 n_left_from, * from, * to_next;
  test_batch_next_t next_index;
  u32 pkts_hashed = 0;
  u32 fake_n_vectors = frame->n_vectors;

  from = vlib_frame_vector_args (frame);
  n_left_from = fake_n_vectors;
  next_index = node->cached_next_index;

  while (n_left_from > 0)
    {
      u32 n_left_to_next;

      vlib_get_next_frame (vm, node, next_index,
			   to_next, n_left_to_next);

      while (n_left_from >= 4 && n_left_to_next >= 2)
	{
          u32 next0 = TEST_BATCH_NEXT_IP4_LOOKUP;
          u32 next1 = TEST_BATCH_NEXT_IP4_LOOKUP;
          u32 bi0, bi1;
	  vlib_buffer_t * b0, * b1;
          
	  /* Prefetch next iteration. */
	  {
	    vlib_buffer_t * p2, * p3;
            
	    p2 = vlib_get_buffer (vm, from[2]);
	    p3 = vlib_get_buffer (vm, from[3]);
            
	    vlib_prefetch_buffer_header (p2, LOAD);
	    vlib_prefetch_buffer_header (p3, LOAD);

	    CLIB_PREFETCH (p2->data, TEST_BATCH_CAL_HASH_NUM * TEST_BATCH_HASH_BYTES, STORE);
	    CLIB_PREFETCH (p3->data, TEST_BATCH_CAL_HASH_NUM * TEST_BATCH_HASH_BYTES, STORE);
	  }

    /* speculatively enqueue b0 and b1 to the current next frame */
	  to_next[0] = bi0 = from[0];
	  to_next[1] = bi1 = from[1];
	  from += 2;
	  to_next += 2;
	  n_left_from -= 2;
	  n_left_to_next -= 2;

	  b0 = vlib_get_buffer (vm, bi0);
	  b1 = vlib_get_buffer (vm, bi1);

    // ASSERT (b0->current_data == 0);
    // ASSERT (b1->current_data == 0);
    
    
    /*check that packet size is grater than hash key size*/
    if (PREDICT_TRUE(b0->current_length >= TEST_BATCH_CAL_HASH_NUM * TEST_BATCH_HASH_BYTES)) {
      int i;
      u64 *pos, hash; 
      pos = vlib_buffer_get_current (b0);
      for (i = 0; i < TEST_BATCH_CAL_HASH_NUM; i++) {
        hash = clib_xxhash (*pos);
        test_batch_main.temp_vec[i] = hash;
        pos += 1;
      }  
    } else {
      /*drop packet*/
      next0 = TEST_BATCH_NEXT_DROP;
    }

    /*check that packet size is grater than hash key size*/
    if (PREDICT_TRUE(b1->current_length >= TEST_BATCH_CAL_HASH_NUM * TEST_BATCH_HASH_BYTES)) {
      int i;
      u64 *pos, hash; 
      pos = vlib_buffer_get_current (b1);
      for (i = 0; i < TEST_BATCH_CAL_HASH_NUM; i++) {
        hash = clib_xxhash (*pos);
        test_batch_main.temp_vec[i] = hash;
        pos += 1;
      }  
    } else {
      /*drop packet*/
      next1 = TEST_BATCH_NEXT_DROP;
    }

    pkts_hashed += 2;
     
    /* verify speculative enqueues, maybe switch current next frame */
    vlib_validate_buffer_enqueue_x2 (vm, node, next_index,
                                      to_next, n_left_to_next,
                                      bi0, bi1, next0, next1);
    }

 while (n_left_from > 0 && n_left_to_next > 0)
	{
    u32 bi0;
	  vlib_buffer_t * b0;
    u32 next0 = TEST_BATCH_NEXT_IP4_LOOKUP;

          /* speculatively enqueue b0 to the current next frame */
	  bi0 = from[0];
	  to_next[0] = bi0;
	  from += 1;
	  to_next += 1;
	  n_left_from -= 1;
	  n_left_to_next -= 1;

	  b0 = vlib_get_buffer (vm, bi0);
    /* 
      * Direct from the driver, we should be at offset 0
      * aka at &b0->data[0]
      */
    //ASSERT (b0->current_data == 0);
    if (PREDICT_TRUE(b0->current_length >= TEST_BATCH_CAL_HASH_NUM * TEST_BATCH_HASH_BYTES)) {
      int i;
      u64 *pos, hash; 
      pos = vlib_buffer_get_current (b0);
      for (i = 0; i < TEST_BATCH_CAL_HASH_NUM; i++) {
        hash = clib_xxhash (*pos);
        test_batch_main.temp_vec[i] = hash;
        pos += 1;
      }  
    } else {
      /*drop packet*/
      next0 = TEST_BATCH_NEXT_DROP;
    }


    pkts_hashed += 1;

          /* verify speculative enqueue, maybe switch current next frame */
	  vlib_validate_buffer_enqueue_x1 (vm, node, next_index,
					   to_next, n_left_to_next,
					   bi0, next0);
	}

      vlib_put_next_frame (vm, node, next_index, n_left_to_next);
    }

  vlib_node_increment_counter (vm, test_batch_node.index, 
                               TEST_BATCH_ERROR_HASHED, pkts_hashed);
  //return frame->n_vectors;
  return frame->n_vectors;
}

/* *INDENT-OFF* */
#ifndef CLIB_MARCH_VARIANT
VLIB_REGISTER_NODE (test_batch_node) = 
{
  .name = "test_batch",
  .vector_size = sizeof (u32),
  .format_trace = format_test_batch_trace,
  .type = VLIB_NODE_TYPE_INTERNAL,
  
  .n_errors = ARRAY_LEN(test_batch_error_strings),
  .error_strings = test_batch_error_strings,

  .n_next_nodes = TEST_BATCH_N_NEXT,

  /* edit / add dispositions here */
  .next_nodes = {
        [TEST_BATCH_NEXT_IP4_LOOKUP] = "ip4-lookup",
        [TEST_BATCH_NEXT_DROP] = "ip4-drop"
  },
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
