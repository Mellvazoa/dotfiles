#include <mach/mach.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>

struct cpu {
  host_t host;
  mach_msg_type_number_t count;
  host_cpu_load_info_data_t load;
  host_cpu_load_info_data_t prev_load;
  bool has_prev_load;

  int user_load;
  int sys_load;
  int total_load;
};

static inline void cpu_init(struct cpu* cpu) {
  memset(cpu, 0, sizeof(*cpu));
  cpu->host = mach_host_self();
  cpu->count = HOST_CPU_LOAD_INFO_COUNT;
  cpu->has_prev_load = false;
}

static inline void cpu_update(struct cpu* cpu) {
  kern_return_t error = host_statistics(cpu->host,
                                        HOST_CPU_LOAD_INFO,
                                        (host_info_t)&cpu->load,
                                        &cpu->count                );

  if (error != KERN_SUCCESS) {
    printf("Error: Could not read cpu host statistics.\n");
    return;
  }

  if (cpu->has_prev_load) {
    uint32_t delta_user = cpu->load.cpu_ticks[CPU_STATE_USER]
                          - cpu->prev_load.cpu_ticks[CPU_STATE_USER];

    uint32_t delta_system = cpu->load.cpu_ticks[CPU_STATE_SYSTEM]
                            - cpu->prev_load.cpu_ticks[CPU_STATE_SYSTEM];

    uint32_t delta_idle = cpu->load.cpu_ticks[CPU_STATE_IDLE]
                          - cpu->prev_load.cpu_ticks[CPU_STATE_IDLE];

    uint64_t total_ticks = (uint64_t)delta_system
                           + (uint64_t)delta_user
                           + (uint64_t)delta_idle;

    if (total_ticks > 0) {
      cpu->user_load = (double)delta_user / (double)total_ticks * 100.0;
      cpu->sys_load = (double)delta_system / (double)total_ticks * 100.0;
      cpu->total_load = cpu->user_load + cpu->sys_load;
    } else {
      cpu->user_load = 0;
      cpu->sys_load = 0;
      cpu->total_load = 0;
    }
  }

  cpu->prev_load = cpu->load;
  cpu->has_prev_load = true;
}
