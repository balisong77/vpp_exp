#define DUAL_PKT_PROCESS_FN(plugin_name)                                       \
  do {                                                                         \
    u64 sum = 0;                                                               \
    for (int index = 0; index < b0->current_length - 16; index++) {            \
      u64 *pos;                                                                \
      pos = vlib_buffer_get_current(b0);                                       \
      u64 num = *(u64 *)pos;                                                   \
      sum = sum + num;                                                         \
    }                                                                          \
    plugin_name##_main.temp_vec[0] = sum;                                      \
    sum = 0;                                                                   \
    for (int index = 0; index < b1->current_length - 16; index++) {            \
      u64 *pos;                                                                \
      pos = vlib_buffer_get_current(b1);                                       \
      u64 num = *(u64 *)pos;                                                   \
      sum = sum + num;                                                         \
    }                                                                          \
    plugin_name##_main.temp_vec[1] = sum;                                      \
  } while (0)

#define SINGLE_PKT_PROCESS_FN(plugin_name)                                     \
  do {                                                                         \
    u64 sum = 0;                                                               \
    for (int index = 0; index < b0->current_length - 16; index++) {            \
      u64 *pos;                                                                \
      pos = vlib_buffer_get_current(b0);                                       \
      u64 num = *(u64 *)pos;                                                   \
      sum = sum + num;                                                         \
    }                                                                          \
    plugin_name##_main.temp_vec[0] = sum;                                      \
  } while (0)