#import "ARRootListController.h"
#import "ARAppsTableController.h"
#import "ARStore.h"

@implementation ARRootListController

- (PSSpecifier *)linkNamed:(NSString *)name action:(SEL)action {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name
                                                   target:self
                                                      set:NULL
                                                      get:NULL
                                                   detail:NULL
                                                     cell:PSLinkCell
                                                     edit:NULL];
    s->action = action;
    return s;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        [specs addObject:[self groupNamed:@"AutoRotate"
                                   footer:@"Master switch for the whole tweak. Configure apps below, then tap Apply."]];
        [specs addObject:[self switchSpecifierNamed:@"Enabled (master)" key:@"Enabled" default:NO]];
#if AR_DEBUG
        [specs addObject:[self switchSpecifierNamed:@"Debug logging" key:@"Debug" default:NO]];
#endif

        [specs addObject:[self groupNamed:@"" footer:@"Apply writes your changes and updates running apps "
                                                     @"(others change on next launch). Nothing takes effect until you Apply."]];
        [specs addObject:[self buttonNamed:@"Apply" action:@selector(applySettings)]];
        [specs addObject:[self buttonNamed:@"Respring" action:@selector(respring)]];

        [specs addObject:[self groupNamed:@"Apps" footer:@"Pick orientations per app. System apps are included."]];
        [specs addObject:[self linkNamed:@"User Apps" action:@selector(openUserApps)]];
        [specs addObject:[self linkNamed:@"System Apps" action:@selector(openSystemApps)]];

        [specs addObject:[self groupNamed:@"" footer:@"Reset clears every app's settings, turns all apps off, and applies immediately."]];
        [specs addObject:[self buttonNamed:@"Reset to defaults" action:@selector(resetSettings)]];

        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)openUserApps {
    ARAppsTableController *vc = [[ARAppsTableController alloc] initWithSystem:NO];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openSystemApps {
    ARAppsTableController *vc = [[ARAppsTableController alloc] initWithSystem:YES];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
