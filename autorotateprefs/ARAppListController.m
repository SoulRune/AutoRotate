#import "ARAppListController.h"
#import "ARStore.h"

@implementation ARAppListController

- (NSString *)bid {
    return [self.specifier propertyForKey:@"bid"] ?: @"";
}

- (NSString *)k:(NSString *)suffix {
    return [ARStore orientationKey:[self bid] suffix:suffix];
}

- (PSSpecifier *)disable:(PSSpecifier *)s when:(BOOL)cond {
    if (cond) [s setProperty:@NO forKey:@"enabled"];
    return s;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        NSString *enableKey = [ARStore enableKey:[self bid]];
        BOOL enabled = [ARStore appEnabled:[self bid]];
        BOOL isSpringBoard = [[self bid] isEqualToString:@"com.apple.springboard"];

        NSString *footer = isSpringBoard
            ? @"Rotates the Home Screen and Lock Screen. Lock Screen works well; the Home "
              @"Screen in landscape is beta — Notification Center, Today View, returning to "
              @"the Home Screen from an app, or exiting the App Switcher can reflow the icons "
              @"until the next device rotation. Respring after applying."
            : @"Lock this app to the ticked orientations. Tick one for a hard lock; "
              @"tick several to allow rotation only among them. Untick all to leave the "
              @"app's own behaviour alone.";
        [specs addObject:[self groupNamed:[self bid] footer:footer]];
        [specs addObject:[self switchSpecifierNamed:@"Enabled" key:enableKey default:NO]];

        [specs addObject:[self groupNamed:@"Orientations" footer:!enabled ? @"Enable this app first." : nil]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Portrait" key:[self k:@"Portrait"] default:NO] when:!enabled]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Portrait upside down" key:[self k:@"UpsideDown"] default:NO] when:!enabled]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Landscape left" key:[self k:@"LandscapeLeft"] default:NO] when:!enabled]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Landscape right" key:[self k:@"LandscapeRight"] default:NO] when:!enabled]];

        _specifiers = [specs copy];
    }
    return _specifiers;
}

// Toggling Enabled greys/reveals the orientation rows.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    if ([[specifier propertyForKey:@"key"] isEqualToString:[ARStore enableKey:[self bid]]]) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

@end
