#include <Carbon/Carbon.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "../sketchybar.h"

static char g_last_code[16] = {0};
static char g_event_name[128] = "keyboard_change";

static void get_layout_code(char *out, size_t out_len) {
  TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
  if (!source) {
    snprintf(out, out_len, "??");
    return;
  }
  CFStringRef sourceId = (CFStringRef)TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
  char idBuf[128] = {0};
  if (sourceId) CFStringGetCString(sourceId, idBuf, sizeof(idBuf), kCFStringEncodingUTF8);
  CFRelease(source);

  if (strstr(idBuf, "Russian") != NULL) {
    snprintf(out, out_len, "RU");
  } else if (strstr(idBuf, "ABC") != NULL || strstr(idBuf, "US") != NULL || strstr(idBuf, "British") != NULL) {
    snprintf(out, out_len, "EN");
  } else {
    char *dot = strrchr(idBuf, '.');
    if (dot && strlen(dot + 1) >= 2) {
      char c1 = (char)toupper((unsigned char)dot[1]);
      char c2 = (char)toupper((unsigned char)dot[2]);
      snprintf(out, out_len, "%c%c", c1, c2);
    } else {
      snprintf(out, out_len, "EN");
    }
  }
}

static void toggle_input_source() {
  TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
  if (!current) return;
  CFStringRef curId = (CFStringRef)TISGetInputSourceProperty(current, kTISPropertyInputSourceID);

  CFArrayRef list = TISCreateInputSourceList(NULL, false);
  if (!list) {
    CFRelease(current);
    return;
  }

  CFIndex count = CFArrayGetCount(list);
  for (CFIndex i = 0; i < count; i++) {
    TISInputSourceRef s = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
    CFStringRef cat = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceCategory);
    CFBooleanRef sel = (CFBooleanRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceIsSelectCapable);
    if (cat && CFStringCompare(cat, kTISCategoryKeyboardInputSource, 0) == kCFCompareEqualTo &&
        sel && CFBooleanGetValue(sel)) {
      CFStringRef sId = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
      if (sId && curId && CFStringCompare(sId, curId, 0) != kCFCompareEqualTo) {
        TISSelectInputSource(s);
        break;
      }
    }
  }

  CFRelease(list);
  CFRelease(current);
}

static void trigger_sketchybar() {
  char code[16];
  get_layout_code(code, sizeof(code));
  if (strcmp(code, g_last_code) != 0) {
    strncpy(g_last_code, code, sizeof(g_last_code) - 1);
    char trigger_message[256];
    snprintf(trigger_message, sizeof(trigger_message), "--trigger '%s' layout='%s'", g_event_name, code);
    sketchybar(trigger_message);
  }
}

static void on_layout_change(CFNotificationCenterRef center,
                             void *observer,
                             CFStringRef name,
                             const void *object,
                             CFDictionaryRef userInfo) {
  trigger_sketchybar();
}

int main(int argc, char** argv) {
  if (argc > 1) {
    if (strcmp(argv[1], "toggle") == 0 || strcmp(argv[1], "--toggle") == 0) {
      toggle_input_source();
      return 0;
    }
    if (strcmp(argv[1], "current") == 0 || strcmp(argv[1], "--current") == 0) {
      char code[16];
      get_layout_code(code, sizeof(code));
      printf("%s\n", code);
      return 0;
    }
    strncpy(g_event_name, argv[1], sizeof(g_event_name) - 1);
  }

  // Register event in sketchybar
  char event_message[256];
  snprintf(event_message, sizeof(event_message), "--add event '%s'", g_event_name);
  sketchybar(event_message);

  // Send initial state
  trigger_sketchybar();

  // Listen to distributed notification for layout changes
  CFNotificationCenterAddObserver(
    CFNotificationCenterGetDistributedCenter(),
    NULL,
    on_layout_change,
    kTISNotifySelectedKeyboardInputSourceChanged,
    NULL,
    CFNotificationSuspensionBehaviorDeliverImmediately
  );

  CFRunLoopRun();
  return 0;
}
