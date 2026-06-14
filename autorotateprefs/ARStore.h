#import <UIKit/UIKit.h>

// Shared storage + app enumeration for the whole prefs bundle.
//
// The panel edits a *draft* plist; +apply copies draft -> applied and notifies the
// injected tweak. Nothing the user toggles takes effect until +apply runs.
@interface ARStore : NSObject

// Paths (rootless-/rootful-aware).
+ (NSString *)draftPath;
+ (NSString *)appliedPath;

// Draft key/value access.
+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;

// Per-app helpers.
+ (NSString *)enableKey:(NSString *)bid;                       // "enabled-<bid>"
+ (NSString *)orientationKey:(NSString *)bid suffix:(NSString *)suffix; // "<bid>-<suffix>"
+ (BOOL)appEnabled:(NSString *)bid;
+ (void)setAppEnabled:(BOOL)value forBundle:(NSString *)bid;

// App listing. Returns @[ @{ @"id": bundleID, @"name": displayName } ], name-sorted.
// system==YES -> system apps, system==NO -> user (App Store) apps. Visible apps only.
+ (NSArray<NSDictionary *> *)appsForSystem:(BOOL)system;

// App icon (AppList, with a private-API fallback). May return nil.
+ (UIImage *)iconForBundle:(NSString *)bid;

// Commit / reset / respring.
+ (void)apply;        // draft -> applied + Darwin notify
+ (void)resetAll;     // wipe draft + applied + notify
+ (void)respring;

@end
