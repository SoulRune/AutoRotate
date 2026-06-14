#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

// Shared base for the PSListController-based pages (root + per-app detail). Persistence
// and apply/reset/respring are delegated to ARStore so the custom table pages share the
// exact same draft/applied storage.
@interface ARListBase : PSListController
- (void)applySettings;   // commit draft -> applied + notify (with confirmation toast)
- (void)resetSettings;   // wipe draft + applied (with confirmation)
- (void)respring;        // restart SpringBoard (with confirmation)
- (PSSpecifier *)switchSpecifierNamed:(NSString *)name key:(NSString *)key default:(BOOL)def;
- (PSSpecifier *)groupNamed:(NSString *)name footer:(NSString *)footer;
- (PSSpecifier *)buttonNamed:(NSString *)name action:(SEL)action;
@end
