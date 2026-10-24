#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <stdbool.h>
#include "../sketchybar.h"

static FILE* g_pipe = NULL;

static void sig_handler(int sig) {
  if (g_pipe) {
    pclose(g_pipe);
    g_pipe = NULL;
  }
  exit(0);
}

// Unicode lower block characters for audio visualizer
static const char* BARS[] = {
  " ", " ", "▂", "▃", "▄", "▅", "▆", "▇", "█"
};

int main(int argc, char** argv) {
  if (argc < 2) {
    printf("Usage: %s <target_item_name> [config_path]\n", argv[0]);
    return 1;
  }

  char* item_name = argv[1];
  char config_path[1024];

  if (argc >= 3) {
    snprintf(config_path, sizeof(config_path), "%s", argv[2]);
  } else {
    char* config_dir = getenv("CONFIG_DIR");
    if (config_dir) {
      snprintf(config_path, sizeof(config_path), "%s/helpers/event_providers/cava_load/cava.conf", config_dir);
    } else {
      snprintf(config_path, sizeof(config_path), "./helpers/event_providers/cava_load/cava.conf");
    }
  }

  signal(SIGTERM, sig_handler);
  signal(SIGINT, sig_handler);

  char cmd[1200];
  snprintf(cmd, sizeof(cmd), "/opt/homebrew/bin/cava -p \"%s\" 2>/dev/null", config_path);

  g_pipe = popen(cmd, "r");
  if (!g_pipe) {
    perror("popen failed for cava");
    return 1;
  }

  char line[256];
  char bar_str[128];
  char sbar_cmd[512];
  bool is_drawing = false;
  int silent_count = 0;

  while (fgets(line, sizeof(line), g_pipe)) {
    bar_str[0] = '\0';
    int total_energy = 0;
    char* token = strtok(line, ";\r\n");
    while (token) {
      int val = atoi(token);
      if (val < 0) val = 0;
      if (val > 8) val = 8;
      total_energy += val;
      strncat(bar_str, BARS[val], sizeof(bar_str) - strlen(bar_str) - 1);
      token = strtok(NULL, ";\r\n");
    }

    if (total_energy > 0) {
      silent_count = 0;
      if (!is_drawing) {
        is_drawing = true;
        snprintf(sbar_cmd, sizeof(sbar_cmd), "--set %s drawing=on", item_name);
        sketchybar(sbar_cmd);
      }
      snprintf(sbar_cmd, sizeof(sbar_cmd), "--set %s label='%s'", item_name, bar_str);
      sketchybar(sbar_cmd);
    } else {
      silent_count++;
      // After ~25 frames of silence (~1s), hide the visualizer automatically
      if (is_drawing && silent_count > 25) {
        is_drawing = false;
        snprintf(sbar_cmd, sizeof(sbar_cmd), "--set %s drawing=off label=''", item_name);
        sketchybar(sbar_cmd);
      }
    }
  }

  if (g_pipe) {
    pclose(g_pipe);
  }
  return 0;
}
