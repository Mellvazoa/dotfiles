#include <Carbon/Carbon.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

extern void _SLPSGetFrontProcess(ProcessSerialNumber* psn);
extern int SLSMainConnectionID();
extern void SLSGetConnectionIDForPSN(int cid, ProcessSerialNumber* psn, int* cid_out);
extern void SLSConnectionGetPID(int cid, pid_t* pid_out);

void ax_init() {
  const void *keys[] = { kAXTrustedCheckOptionPrompt };
  const void *values[] = { kCFBooleanTrue };

  CFDictionaryRef options = CFDictionaryCreate(kCFAllocatorDefault,
                                               keys,
                                               values,
                                               1,
                                               &kCFCopyStringDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks);
  bool trusted = AXIsProcessTrustedWithOptions(options);
  CFRelease(options);
  if (!trusted) exit(1);
}

AXUIElementRef ax_get_front_app() {
  ProcessSerialNumber psn;
  _SLPSGetFrontProcess(&psn);
  int target_cid;
  SLSGetConnectionIDForPSN(SLSMainConnectionID(), &psn, &target_cid);

  pid_t pid;
  SLSConnectionGetPID(target_cid, &pid);
  AXUIElementRef app = AXUIElementCreateApplication(pid);
  // Never hang on unresponsive apps
  if (app) AXUIElementSetMessagingTimeout(app, 0.4f);
  return app;
}

// Returns the top-level menubar children (caller releases both).
static bool get_menubar_children(AXUIElementRef app,
                                 AXUIElementRef* menubar_out,
                                 CFArrayRef* children_out) {
  AXUIElementRef menubar = NULL;
  CFArrayRef children = NULL;
  if (AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute,
                                    (CFTypeRef*)&menubar) != kAXErrorSuccess)
    return false;
  if (AXUIElementCopyAttributeValue(menubar, kAXVisibleChildrenAttribute,
                                    (CFTypeRef*)&children) != kAXErrorSuccess) {
    CFRelease(menubar);
    return false;
  }
  *menubar_out = menubar;
  *children_out = children;
  return true;
}

// Returns the AXMenu items array for a top-level menu element (caller releases).
static CFArrayRef get_menu_items(AXUIElementRef top_item) {
  CFArrayRef sub = NULL;
  if (AXUIElementCopyAttributeValue(top_item, kAXChildrenAttribute,
                                    (CFTypeRef*)&sub) != kAXErrorSuccess || !sub)
    return NULL;
  CFArrayRef items = NULL;
  if (CFArrayGetCount(sub) > 0) {
    AXUIElementRef menu = (AXUIElementRef)CFArrayGetValueAtIndex(sub, 0);
    if (AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute,
                                      (CFTypeRef*)&items) != kAXErrorSuccess)
      items = NULL;
  }
  CFRelease(sub);
  return items;
}

// Print top-level menu titles (index 1 .. count-1)
void print_top_menus(AXUIElementRef app) {
  AXUIElementRef menubar = NULL;
  CFArrayRef children = NULL;
  if (!get_menubar_children(app, &menubar, &children)) return;

  int count = CFArrayGetCount(children);
  for (int i = 1; i < count; i++) {
    AXUIElementRef item = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
    CFTypeRef title = NULL;
    AXUIElementCopyAttributeValue(item, kAXTitleAttribute, &title);
    if (title) {
      char buf[256] = {0};
      CFStringGetCString((CFStringRef)title, buf, sizeof(buf), kCFStringEncodingUTF8);
      printf("%s\n", buf);
      CFRelease(title);
    }
  }

  CFRelease(children);
  CFRelease(menubar);
}

// Translate the AX command character into something our font can draw.
// Appends to `out`. Returns false if the key has no printable representation.
static bool append_key(CFStringRef key, char* out, size_t out_len) {
  if (CFStringGetLength(key) == 0) return false;
  UniChar c = CFStringGetCharacterAtIndex(key, 0);
  const char* sym = NULL;
  char fbuf[8];

  switch (c) {
    case 0xF700: sym = "↑"; break;
    case 0xF701: sym = "↓"; break;
    case 0xF702: sym = "←"; break;
    case 0xF703: sym = "→"; break;
    case 0xF728: sym = "⌦"; break;
    case 0xF729: sym = "↖"; break;
    case 0xF72B: sym = "↘"; break;
    case 0xF72C: sym = "⇞"; break;
    case 0xF72D: sym = "⇟"; break;
    case 0x0D:
    case 0x03:   sym = "↩"; break;
    case 0x08:
    case 0x7F:   sym = "⌫"; break;
    case 0x1B:   sym = "⎋"; break;
    case 0x09:   sym = "⇥"; break;
    case 0x20:   sym = "Space"; break;
    default: break;
  }

  if (!sym && c >= 0xF704 && c <= 0xF70F) {          // F1 .. F12
    snprintf(fbuf, sizeof(fbuf), "F%d", c - 0xF704 + 1);
    sym = fbuf;
  }

  if (sym) {
    strncat(out, sym, out_len - strlen(out) - 1);
    return true;
  }

  // Any other private-use / non-BMP / control char => font can't draw it
  if ((c >= 0xE000 && c <= 0xF8FF) || (c >= 0xD800 && c <= 0xDFFF) || c < 0x20)
    return false;

  char buf[16] = {0};
  CFStringGetCString(key, buf, sizeof(buf), kCFStringEncodingUTF8);
  strncat(out, buf, out_len - strlen(out) - 1);
  return true;
}

static void format_shortcut(CFTypeRef cmd_char, CFTypeRef cmd_mod,
                            char* out, size_t out_len) {
  out[0] = '\0';
  if (!cmd_char || CFGetTypeID(cmd_char) != CFStringGetTypeID()) return;

  char keybuf[64] = {0};
  if (!append_key((CFStringRef)cmd_char, keybuf, sizeof(keybuf))) return;
  if (keybuf[0] == '\0') return;

  int mod_val = 0;
  if (cmd_mod && CFGetTypeID(cmd_mod) == CFNumberGetTypeID())
    CFNumberGetValue((CFNumberRef)cmd_mod, kCFNumberIntType, &mod_val);

  // 0x1 = Shift, 0x2 = Option, 0x4 = Control, 0x8 = no Command
  char mods[32] = {0};
  if (mod_val & 0x4) strcat(mods, "⌃");
  if (mod_val & 0x2) strcat(mods, "⌥");
  if (mod_val & 0x1) strcat(mods, "⇧");
  if (!(mod_val & 0x8)) strcat(mods, "⌘");

  snprintf(out, out_len, "%s%s", mods, keybuf);
}

// Print every item of a top-level menu.
// Line format: ID \t TITLE \t SHORTCUT \t ENABLED \t HAS_SUBMENU
static void print_items_of(AXUIElementRef top_item) {
  CFArrayRef items = get_menu_items(top_item);
  if (!items) return;

  CFStringRef attr_names[] = {
    kAXTitleAttribute,
    kAXEnabledAttribute,
    kAXMenuItemCmdCharAttribute,
    kAXMenuItemCmdModifiersAttribute,
    kAXChildrenAttribute,
  };
  CFArrayRef attrs = CFArrayCreate(NULL, (const void**)attr_names, 5,
                                   &kCFTypeArrayCallBacks);

  int count = CFArrayGetCount(items);
  for (int j = 0; j < count; j++) {
    AXUIElementRef mi = (AXUIElementRef)CFArrayGetValueAtIndex(items, j);

    // One IPC round-trip for all five attributes
    CFArrayRef vals = NULL;
    AXUIElementCopyMultipleAttributeValues(mi, attrs, 0, &vals);

    char title_buf[256] = {0};
    int  is_enabled  = 1;
    int  has_submenu = 0;
    char shortcut[96] = {0};

    if (vals && CFArrayGetCount(vals) == 5) {
      CFTypeRef t = CFArrayGetValueAtIndex(vals, 0);
      if (t && CFGetTypeID(t) == CFStringGetTypeID())
        CFStringGetCString((CFStringRef)t, title_buf, sizeof(title_buf),
                           kCFStringEncodingUTF8);

      CFTypeRef e = CFArrayGetValueAtIndex(vals, 1);
      if (e && CFGetTypeID(e) == CFBooleanGetTypeID())
        is_enabled = CFBooleanGetValue((CFBooleanRef)e) ? 1 : 0;

      format_shortcut(CFArrayGetValueAtIndex(vals, 2),
                      CFArrayGetValueAtIndex(vals, 3),
                      shortcut, sizeof(shortcut));

      CFTypeRef ch = CFArrayGetValueAtIndex(vals, 4);
      if (ch && CFGetTypeID(ch) == CFArrayGetTypeID() &&
          CFArrayGetCount((CFArrayRef)ch) > 0)
        has_submenu = 1;
    }
    if (vals) CFRelease(vals);

    bool is_separator = (title_buf[0] == '\0');
    printf("%d\t%s\t%s\t%d\t%d\n",
           j,
           is_separator ? "---" : title_buf,
           shortcut,
           is_separator ? 0 : is_enabled,
           has_submenu);
  }

  CFRelease(attrs);
  CFRelease(items);
}

void print_subitems(AXUIElementRef app, int menu_index) {
  AXUIElementRef menubar = NULL;
  CFArrayRef children = NULL;
  if (!get_menubar_children(app, &menubar, &children)) return;

  if (menu_index >= 0 && menu_index < CFArrayGetCount(children))
    print_items_of((AXUIElementRef)CFArrayGetValueAtIndex(children, menu_index));

  CFRelease(children);
  CFRelease(menubar);
}

// Print the items of ALL top-level menus in a single pass.
// Each menu is introduced by a line "#<menu_index>".
void print_all(AXUIElementRef app) {
  AXUIElementRef menubar = NULL;
  CFArrayRef children = NULL;
  if (!get_menubar_children(app, &menubar, &children)) return;

  int count = CFArrayGetCount(children);
  for (int i = 1; i < count; i++) {
    printf("#%d\n", i);
    print_items_of((AXUIElementRef)CFArrayGetValueAtIndex(children, i));
  }

  CFRelease(children);
  CFRelease(menubar);
}

void click_subitem(AXUIElementRef app, int menu_index, int subitem_index) {
  AXUIElementRef menubar = NULL;
  CFArrayRef children = NULL;
  if (!get_menubar_children(app, &menubar, &children)) return;

  if (menu_index >= 0 && menu_index < CFArrayGetCount(children)) {
    AXUIElementRef top = (AXUIElementRef)CFArrayGetValueAtIndex(children, menu_index);
    CFArrayRef items = get_menu_items(top);
    if (items) {
      if (subitem_index >= 0 && subitem_index < CFArrayGetCount(items)) {
        AXUIElementRef mi = (AXUIElementRef)CFArrayGetValueAtIndex(items, subitem_index);
        AXUIElementPerformAction(mi, kAXPressAction);
      }
      CFRelease(items);
    }
  }

  CFRelease(children);
  CFRelease(menubar);
}

int main(int argc, char** argv) {
  if (argc < 2) {
    printf("Usage:\n");
    printf("  %s -l                    List top-level menus\n", argv[0]);
    printf("  %s -items <menu_id>      List items of menu <menu_id>\n", argv[0]);
    printf("  %s -all                  List items of every menu (#id headers)\n", argv[0]);
    printf("  %s -click <menu_id> <id> Click item <id> in menu <menu_id>\n", argv[0]);
    return 0;
  }

  ax_init();
  AXUIElementRef app = ax_get_front_app();
  if (!app) return 1;

  if (strcmp(argv[1], "-l") == 0) {
    print_top_menus(app);
  } else if (strcmp(argv[1], "-all") == 0) {
    print_all(app);
  } else if (argc >= 3 && strcmp(argv[1], "-items") == 0) {
    print_subitems(app, atoi(argv[2]));
  } else if (argc >= 4 && strcmp(argv[1], "-click") == 0) {
    click_subitem(app, atoi(argv[2]), atoi(argv[3]));
  }

  CFRelease(app);
  return 0;
}
