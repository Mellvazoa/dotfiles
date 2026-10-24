/*
 * SquareCorners – force square (radius 0) window corners on macOS.
 *
 * Designed for Ammonia tweak injection (DYLD_INSERT via libopener).
 * Unlike AppleSharpener, this hooks NSWindow in ALL GUI processes,
 * not just the Dock.
 *
 * Build:
 *   clang -dynamiclib -framework Foundation -framework AppKit \
 *         -arch arm64 -arch arm64e \
 *         -o libsquare_corners.dylib square_corners.m
 *
 * Install:
 *   sudo cp libsquare_corners.dylib /private/var/ammonia/core/tweaks/
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static IMP orig_setCornerRadius = NULL;

// ── Hook: always set corner radius to 0 ─────────────────────────────
static void hooked_setCornerRadius(id self, SEL _cmd, CGFloat radius) {
    if (orig_setCornerRadius) {
        ((void (*)(id, SEL, CGFloat))orig_setCornerRadius)(self, _cmd, 0.0);
    }
}

// ── Hook: return empty corner mask (no rounded corners) ──────────────
static NSUInteger hooked_cornerMask(id self, SEL _cmd) {
    return 0;  // 0 = no corners rounded
}

// ── Constructor: runs when dylib is loaded into any process ──────────
__attribute__((constructor))
static void square_corners_init(void) {
    @autoreleasepool {
        // Only activate in processes that have AppKit (= GUI apps).
        // CLI tools, daemons, etc. won't have NSWindow and are skipped.
        Class cls = NSClassFromString(@"NSWindow");
        if (!cls) return;

        Method m;

        // Swizzle _setCornerRadius: → always 0
        m = class_getInstanceMethod(cls, NSSelectorFromString(@"_setCornerRadius:"));
        if (m) {
            orig_setCornerRadius = method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_setCornerRadius);
        }

        // Swizzle _cornerMask → 0 (square mask)
        m = class_getInstanceMethod(cls, NSSelectorFromString(@"_cornerMask"));
        if (m) {
            method_setImplementation(m, (IMP)hooked_cornerMask);
        }

        NSLog(@"[SquareCorners] Activated in %@ (bundle: %@)",
              [[NSProcessInfo processInfo] processName],
              [[NSBundle mainBundle] bundleIdentifier] ?: @"(none)");
    }
}
