/*
 * test_batch.c - skeleton vpp engine plug-in
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

#include "vppinfra/vec.h"
#include <vnet/vnet.h>
#include <vnet/plugin/plugin.h>
#include <test_batch/test_batch.h>

#include <vlibapi/api.h>
#include <vlibmemory/api.h>
#include <vpp/app/version.h>
#include <stdbool.h>

#include <test_batch/test_batch.api_enum.h>
#include <test_batch/test_batch.api_types.h>

#define REPLY_MSG_ID_BASE tmp->msg_id_base
#include <vlibapi/api_helper_macros.h>

test_batch_main_t test_batch_main;

/* Action function shared between message handler and debug CLI */

int test_batch_enable_disable (test_batch_main_t * tmp, u32 sw_if_index,
                                   int enable_disable)
{
  vnet_sw_interface_t * sw;
  int rv = 0;

  /* Utterly wrong? */
  if (pool_is_free_index (tmp->vnet_main->interface_main.sw_interfaces,
                          sw_if_index))
    return VNET_API_ERROR_INVALID_SW_IF_INDEX;

  /* Not a physical port? */
  sw = vnet_get_sw_interface (tmp->vnet_main, sw_if_index);
  if (sw->type != VNET_SW_INTERFACE_TYPE_HARDWARE)
    return VNET_API_ERROR_INVALID_SW_IF_INDEX;

  test_batch_create_periodic_process (tmp);

  vnet_feature_enable_disable ("device-input", "test_batch",
                               sw_if_index, enable_disable, 0, 0);

  /* Send an event to enable/disable the periodic scanner process */
  vlib_process_signal_event (tmp->vlib_main,
                             tmp->periodic_node_index,
                             TEST_BATCH_EVENT_PERIODIC_ENABLE_DISABLE,
                            (uword)enable_disable);
  return rv;
}

static clib_error_t *
test_batch_enable_disable_command_fn (vlib_main_t * vm,
                                   unformat_input_t * input,
                                   vlib_cli_command_t * cmd)
{
  test_batch_main_t * tmp = &test_batch_main;
  u32 sw_if_index = ~0;
  int enable_disable = 1;

  int rv;

  while (unformat_check_input (input) != UNFORMAT_END_OF_INPUT)
    {
      if (unformat (input, "disable"))
        enable_disable = 0;
      else if (unformat (input, "%U", unformat_vnet_sw_interface,
                         tmp->vnet_main, &sw_if_index))
        ;
      else
        break;
  }

  if (sw_if_index == ~0)
    return clib_error_return (0, "Please specify an interface...");

  rv = test_batch_enable_disable (tmp, sw_if_index, enable_disable);

  switch(rv)
    {
  case 0:
    break;

  case VNET_API_ERROR_INVALID_SW_IF_INDEX:
    return clib_error_return
      (0, "Invalid interface, only works on physical ports");
    break;

  case VNET_API_ERROR_UNIMPLEMENTED:
    return clib_error_return (0, "Device driver doesn't support redirection");
    break;

  default:
    return clib_error_return (0, "test_batch_enable_disable returned %d",
                              rv);
    }
  return 0;
}

/* *INDENT-OFF* */
VLIB_CLI_COMMAND (test_batch_enable_disable_command, static) =
{
  .path = "test_batch enable-disable",
  .short_help =
  "test_batch enable-disable <interface-name> [disable]",
  .function = test_batch_enable_disable_command_fn,
};
/* *INDENT-ON* */

/* API message handler */
static void vl_api_test_batch_enable_disable_t_handler
(vl_api_test_batch_enable_disable_t * mp)
{
  vl_api_test_batch_enable_disable_reply_t * rmp;
  test_batch_main_t * tmp = &test_batch_main;
  int rv;

  rv = test_batch_enable_disable (tmp, ntohl(mp->sw_if_index),
                                      (int) (mp->enable_disable));

  REPLY_MACRO(VL_API_TEST_BATCH_ENABLE_DISABLE_REPLY);
}

/* API definitions */
#include <test_batch/test_batch.api.c>

static clib_error_t * test_batch_init (vlib_main_t * vm)
{
  test_batch_main_t * tmp = &test_batch_main;
  clib_error_t * error = 0;

  tmp->vlib_main = vm;
  tmp->vnet_main = vnet_get_main();

  /* Add our API messages to the global name_crc hash table */
  tmp->msg_id_base = setup_message_id_table ();

  /* Alloc temp data*/
  vec_resize(tmp->temp_vec, TEST_BATCH_CAL_HASH_NUM);
  vec_validate(tmp->temp_vec, TEST_BATCH_CAL_HASH_NUM - 1);

  return error;
}

VLIB_INIT_FUNCTION (test_batch_init);

/* *INDENT-OFF* */
VNET_FEATURE_INIT (test_batch, static) =
{
  .arc_name = "ip4-unicast",
  .node_name = "test_batch",
  .runs_before = VNET_FEATURES ("ip4-lookup"),
  .runs_after = VNET_FEATURES ("ip4-input", "ip4-input-no-checksum")
};
/* *INDENT-ON */

/* *INDENT-OFF* */
VLIB_PLUGIN_REGISTER () =
{
  .version = VPP_BUILD_VER,
  .description = "test_batch plugin description goes here",
};
/* *INDENT-ON* */

/*
 * fd.io coding-style-patch-verification: ON
 *
 * Local Variables:
 * eval: (c-set-style "gnu")
 * End:
 */
