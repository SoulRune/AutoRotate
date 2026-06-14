// AutoRotate — per-app orientation lock for iOS 15–16+ (rootless/rootful).
//
// The dylib is injected into every UIKit process (Filter = com.apple.UIKit), so it
// runs inside each app — system apps included. On launch it reads the *applied*
// preferences, finds its own bundle id, and if that app is enabled it hard-locks the
// interface to exactly the orientations the user ticked.
//
// "Applied" vs "draft": the Settings panel edits a draft plist. Nothing takes effect
// until the user taps Apply, which copies draft -> applied and posts a Darwin
// notification. Apps therefore never change behaviour on their own — only on Apply
// (live, for running apps) or at next launch (which reads the applied plist).

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Applied preferences live here. The injected sandbox can read "/var/jb/..." on
// rootless; rootful keeps the bare "/var/mobile/..." path.
static NSString *AppliedPlistPath(void) {
    NSString *root = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"/var/jb" : @"";
    return [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/com.i0stweak3r-sr.autorotate.applied.plist", root];
}

// Debug logging is compiled in only with -DAR_DEBUG=1 (`make package AR_DEBUG=1`). In a
// release build ARLog() is a no-op macro and none of the logger code, the "Debug" pref,
// or the marker-file plumbing exists.
#if AR_DEBUG
static BOOL gDebug = NO;
static NSString *JBRoot(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"/var/jb" : @"";
}
static NSString *LogPath(void) {
    return [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/com.i0stweak3r-sr.autorotate.debug.log", JBRoot()];
}
// Logging is on when either the "Debug" pref is applied OR a marker file exists. The
// marker decouples diagnosis from the apply pipeline: `touch` it over SSH and every
// process that loads the dylib logs, no matter what the prefs say.
static NSString *MarkerPath(void) {
    return [NSString stringWithFormat:@"%@/var/mobile/autorotate.debug", JBRoot()];
}
static BOOL DebugOn(void) {
    return gDebug || [[NSFileManager defaultManager] fileExistsAtPath:MarkerPath()];
}
static void ARLogWrite(NSString *line) {
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = LogPath();
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) { @try { [fh seekToEndOfFile]; [fh writeData:data]; } @catch (__unused id e) {} [fh closeFile]; }
    else    { [data writeToFile:path atomically:YES]; }
}
static void ARLog(NSString *fmt, ...) {
    if (!DebugOn()) return;
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
    ARLogWrite([NSString stringWithFormat:@"%@ [%@] %@\n", [NSDate date], bid, msg]);
}
#else
#define ARLog(...) ((void)0)
#endif

// Resolved state for the current process.
static BOOL gMasterEnabled = NO;   // global master switch
static BOOL gAppEnabled    = NO;   // this app ticked on
static UIInterfaceOrientationMask gMask = 0;          // allowed orientations
static UIInterfaceOrientation gPreferred = UIInterfaceOrientationPortrait; // launch orientation

// Active == we should override this process's orientation behaviour.
static inline BOOL Active(void) {
    return gMasterEnabled && gAppEnabled && gMask != 0;
}

// A single-orientation mask is a hard lock; multi-orientation masks should rotate freely
// among the allowed set (no forced re-assert).
static inline BOOL MaskIsSingle(void) {
    return gMask != 0 && (gMask & (gMask - 1)) == 0;
}

// Pick a single concrete orientation for presentation / forced launch rotation.
// Prefer portrait, then landscape-right (the "natural" landscape), then the rest.
static UIInterfaceOrientation PreferredFromMask(UIInterfaceOrientationMask mask) {
    if (mask & UIInterfaceOrientationMaskPortrait)           return UIInterfaceOrientationPortrait;
    if (mask & UIInterfaceOrientationMaskLandscapeRight)     return UIInterfaceOrientationLandscapeRight;
    if (mask & UIInterfaceOrientationMaskLandscapeLeft)      return UIInterfaceOrientationLandscapeLeft;
    if (mask & UIInterfaceOrientationMaskPortraitUpsideDown) return UIInterfaceOrientationPortraitUpsideDown;
    return UIInterfaceOrientationPortrait;
}

static void LoadPrefs(void) {
    gMasterEnabled = NO; gAppEnabled = NO; gMask = 0;

    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (bid.length == 0) return;

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:AppliedPlistPath()];
#if AR_DEBUG
    gDebug = [prefs[@"Debug"] boolValue];
#endif
    if (!prefs) { ARLog(@"LoadPrefs: no applied plist at %@", AppliedPlistPath()); return; }

    gMasterEnabled = [prefs[@"Enabled"] boolValue];
    gAppEnabled    = [prefs[[@"enabled-" stringByAppendingString:bid]] boolValue];

    UIInterfaceOrientationMask mask = 0;
    if ([prefs[[bid stringByAppendingString:@"-Portrait"]] boolValue])      mask |= UIInterfaceOrientationMaskPortrait;
    if ([prefs[[bid stringByAppendingString:@"-UpsideDown"]] boolValue])    mask |= UIInterfaceOrientationMaskPortraitUpsideDown;
    if ([prefs[[bid stringByAppendingString:@"-LandscapeLeft"]] boolValue]) mask |= UIInterfaceOrientationMaskLandscapeLeft;
    if ([prefs[[bid stringByAppendingString:@"-LandscapeRight"]] boolValue])mask |= UIInterfaceOrientationMaskLandscapeRight;

    gMask = mask;
    gPreferred = PreferredFromMask(mask);

    ARLog(@"LoadPrefs: master=%d appEnabled=%d mask=0x%lx preferred=%ld active=%d",
          gMasterEnabled, gAppEnabled, (unsigned long)gMask, (long)gPreferred, Active());
}

// --- Per-class supportedInterfaceOrientations override ----------------------------
//
// The app-level _supportedInterfaceOrientationsForWindow: hook isn't enough: UIKit
// validates rotations against the *view controller's* supportedInterfaceOrientations,
// and many apps' controllers override that method (so the %hook on UIViewController's
// base implementation never runs for them — e.g. Settings' root reports portrait only).
//
// We can't hook every subclass at load time, so we swizzle on demand: walk the live
// view-controller tree and replace supportedInterfaceOrientations on each concrete class
// with one that returns our mask while active (and the original otherwise). Dedup by the
// Method pointer so inherited implementations are swizzled once.
static NSMutableSet *gSwizzled;  // NSValues wrapping swizzled Method pointers

static void SwizzleSIO(Class cls) {
    if (!cls) return;
    SEL sel = @selector(supportedInterfaceOrientations);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    // The base UIViewController implementation is already handled by the %hook below.
    if (m == class_getInstanceMethod([UIViewController class], sel)) return;
    NSValue *key = [NSValue valueWithPointer:m];
    if ([gSwizzled containsObject:key]) return;
    [gSwizzled addObject:key];

    __block IMP oldIMP = NULL;
    IMP newIMP = imp_implementationWithBlock(^UIInterfaceOrientationMask(__unused id me) {
        if (Active()) return gMask;
        if (oldIMP) return ((UIInterfaceOrientationMask (*)(id, SEL))oldIMP)(me, sel);
        return UIInterfaceOrientationMaskAll;
    });
    oldIMP = method_setImplementation(m, newIMP);
}

// Swizzle the class of every controller reachable from a window's root: the root, its
// presented chain, and all children (nav/tab/split containers).
static void SwizzleVCTree(UIViewController *vc) {
    if (![vc isKindOfClass:[UIViewController class]]) return;
    SwizzleSIO(object_getClass(vc));
    SwizzleVCTree(vc.presentedViewController);
    for (UIViewController *child in vc.childViewControllers) SwizzleVCTree(child);
}

static void SwizzleAllWindows(void) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) SwizzleVCTree(w.rootViewController);
    }
}

// Push the chosen orientation onto the running app. This is the anti-"snaps back to
// portrait at launch" / anti-"won't start in the chosen mode" measure: returning the
// mask alone isn't always enough for system apps, so we also actively drive the
// geometry to the preferred orientation.
static void ForceOrientation(void) {
    if (!Active()) return;

    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;

    UIInterfaceOrientationMask mask = gMask;
    UIInterfaceOrientation target = gPreferred;

    // Make the live view controllers agree with our mask before asking UIKit to rotate —
    // otherwise the geometry request is rejected by a controller that reports portrait.
    SwizzleAllWindows();

    // SpringBoard rejects programmatic geometry updates ("window display mode doesn't
    // allow…") and rotates via its own home-screen path instead, so skip the request there.
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;

    // iOS 16 geometry API. Reached purely through objc_msgSend / NSClassFromString so the
    // SDK's iOS-16 symbols are never named in source — that avoids both the
    // -Wunguarded-availability error and the __isPlatformVersionAtLeast builtin that
    // @available would emit (the Linux toolchain can't link it).
    SEL reqSel = NSSelectorFromString(@"requestGeometryUpdateWithPreferences:errorHandler:");
    SEL initSel = NSSelectorFromString(@"initWithInterfaceOrientations:");
    SEL needsSel = NSSelectorFromString(@"setNeedsUpdateOfSupportedInterfaceOrientations");
    Class geoClass = NSClassFromString(@"UIWindowSceneGeometryPreferencesIOS");
    BOOL ios16 = (geoClass && [UIWindowScene instancesRespondToSelector:reqSel]);
    ARLog(@"ForceOrientation: path=%@ mask=0x%lx target=%ld", ios16 ? @"iOS16" : @"iOS15", (unsigned long)mask, (long)target);
    if (ios16) {
        void (^errHandler)(NSError *) = ^(NSError *error) { ARLog(@"requestGeometryUpdate error: %@", error); };
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            ARLog(@"  scene before: interfaceOrientation=%ld", (long)ws.interfaceOrientation);
            id geo = ((id (*)(id, SEL, NSUInteger))objc_msgSend)([geoClass alloc], initSel, mask);
            ((void (*)(id, SEL, id, id))objc_msgSend)(ws, reqSel, geo, errHandler);
            for (UIWindow *w in ws.windows) {
                UIViewController *root = w.rootViewController;
                if ([root respondsToSelector:needsSel])
                    ((void (*)(id, SEL))objc_msgSend)(root, needsSel);
            }
        }
    } else {
        // iOS 15: nudge the device orientation, then ask UIKit to re-evaluate. The
        // supportedInterfaceOrientations hook clamps it to the allowed set.
        UIDeviceOrientation devO = UIDeviceOrientationPortrait;
        switch (target) {
            case UIInterfaceOrientationPortrait:           devO = UIDeviceOrientationPortrait; break;
            case UIInterfaceOrientationPortraitUpsideDown: devO = UIDeviceOrientationPortraitUpsideDown; break;
            // Device vs interface landscape are mirrored.
            case UIInterfaceOrientationLandscapeLeft:      devO = UIDeviceOrientationLandscapeRight; break;
            case UIInterfaceOrientationLandscapeRight:     devO = UIDeviceOrientationLandscapeLeft; break;
            default: break;
        }
        [[UIDevice currentDevice] setValue:@(devO) forKey:@"orientation"];
        [UIViewController attemptRotationToDeviceOrientation];
    }
}

static void ForceOrientationSoon(void) {
    // Let the scene/window settle first, then force.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ForceOrientation(); });
}

#pragma mark - Orientation hooks

// The authoritative gate. UIKit calls this to decide a window's allowed orientations —
// it already aggregates the whole view-controller hierarchy, the app delegate and
// Info.plist, so overriding it here clamps everything to our mask regardless of which
// view controllers override supportedInterfaceOrientations themselves. This is what
// actually stops the free-spin when the device is rotated.
%hook UIApplication
- (UIInterfaceOrientationMask)_supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    if (Active()) return gMask;
    return %orig;
}
// Public counterpart, present on some versions; harmless to also clamp.
- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    if (Active()) return gMask;
    return %orig;
}
%end

// Secondary clamps for view controllers that don't override these (and so fall through
// to UIViewController's implementations). The on-demand swizzle handles controllers that
// *do* override; these cover the rest.
%hook UIViewController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (Active()) return gMask;
    return %orig;
}
- (BOOL)shouldAutorotate {
    if (Active()) return YES;
    return %orig;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (Active()) return gPreferred;
    return %orig;
}
%end

#pragma mark - SpringBoard (home / lock screen / system UI)

// SpringBoard doesn't rotate via the standard UIViewController path: its home screen is
// gated by SpringBoard-specific rotation switches and the physical-orientation lock. We
// enable rotation and clamp the home-screen controller to our mask; the generic swizzle +
// geometry request (which also run here) then drive the actual rotation. Only %init'd in
// the SpringBoard process.
%group SBRotation

%hook SpringBoard
- (long long)homeScreenRotationStyle {
    if (Active()) {
        // 1 = iPad grid (breaks layout + vertical dock on iPhone); 2 = iPhone "Plus"
        // landscape layout (correct icon grid + horizontal dock). Pick per device.
        return [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad ? 1 : 2;
    }
    return %orig;
}
%end

%hook SBHomeScreenViewController
- (BOOL)homeScreenSupportsRotation {
    if (Active()) return YES;
    return %orig;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (Active()) return gMask;
    return %orig;
}
%end

// Don't let the user's rotation lock suppress our forced orientation.
%hook SBOrientationLockManager
- (BOOL)isUserLocked {
    if (Active()) return NO;
    return %orig;
}
%end

%end // group SBRotation

#pragma mark - Lifecycle

static void HandleApplied(CFNotificationCenterRef center, void *observer, CFStringRef name,
                          const void *object, CFDictionaryRef userInfo) {
    ARLog(@"HandleApplied: reload");
    LoadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{ ForceOrientation(); });
}

%ctor {
    @autoreleasepool {
        gSwizzled = [NSMutableSet set];
        NSString *procBID = [[NSBundle mainBundle] bundleIdentifier];
        LoadPrefs();              // sets gDebug, so logging below honours the switch
        ARLog(@"ctor: dylib loaded");

        // Initialise the default (ungrouped) hooks. Required explicitly because the named
        // group below means Logos no longer auto-inserts this for us.
        %init;
        // SpringBoard-specific rotation hooks, only inside SpringBoard.
        if ([procBID isEqualToString:@"com.apple.springboard"]) %init(SBRotation);

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        HandleApplied,
                                        CFSTR("com.i0stweak3r-sr.autorotate/applied"), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        // Force the orientation once the app is up and again whenever a scene activates,
        // covering cold launch and resume-from-background.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:nil
                                                      usingBlock:^(NSNotification *n) { ForceOrientationSoon(); }];
        // Deployment target is iOS 15, so the scene notification is always available.
        [[NSNotificationCenter defaultCenter] addObserverForName:UISceneDidActivateNotification
                                                          object:nil queue:nil
                                                      usingBlock:^(NSNotification *n) { ForceOrientationSoon(); }];
        // If the user physically rotates the device, re-assert our orientation: catches any
        // controller that slipped through and pins multi-orientation locks to the preferred.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
                                                          object:nil queue:nil
                                                      usingBlock:^(NSNotification *n) {
            if (Active()) {
                ARLog(@"DeviceOrientationDidChange: device=%ld", (long)[UIDevice currentDevice].orientation);
                // Only re-assert a single-orientation hard lock; multi-orientation locks
                // rotate freely among the allowed set (forcing here would snap upside-down
                // flips to the preferred orientation).
                if (MaskIsSingle()) ForceOrientationSoon();
            }
        }];
    }
}
