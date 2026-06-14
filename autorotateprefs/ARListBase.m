#import "ARListBase.h"
#import "ARStore.h"
#import <UIKit/UIKit.h>

@interface ARListBase ()
- (void)toast:(NSString *)title message:(NSString *)message;
@end

@implementation ARListBase

#pragma mark - Draft persistence (PSSpecifier get/set, routed to ARStore)

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:[ARStore draftPath]];
    id value = settings[[specifier propertyForKey:@"key"]];
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    // Draft only — no auto-apply. -applySettings is the single commit point.
    [ARStore setBool:[value boolValue] forKey:[specifier propertyForKey:@"key"]];
}

#pragma mark - Apply / Reset / Respring

- (void)applySettings {
    [ARStore apply];
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [fb impactOccurred];
    [self toast:@"Applied" message:@"Settings are now live. Already-running apps update immediately; "
                                   @"others apply on next launch."];
}

- (void)resetSettings {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Reset to defaults?"
                                                              message:@"Clears every app's orientation settings and turns all apps off."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
        [ARStore resetAll];
        self->_specifiers = nil;
        [self reloadSpecifiers];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)respring {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Respring?"
                                                              message:@"Restarts SpringBoard. Use this if an app won't pick up its new orientation."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
        [ARStore respring];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)toast:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Specifier builders

- (PSSpecifier *)switchSpecifierNamed:(NSString *)name key:(NSString *)key default:(BOOL)def {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name
                                                   target:self
                                                      set:@selector(setPreferenceValue:specifier:)
                                                      get:@selector(readPreferenceValue:)
                                                   detail:nil
                                                     cell:PSSwitchCell
                                                     edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@(def) forKey:@"default"];
    return s;
}

- (PSSpecifier *)groupNamed:(NSString *)name footer:(NSString *)footer {
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:name];
    if (footer) [g setProperty:footer forKey:@"footerText"];
    return g;
}

- (PSSpecifier *)buttonNamed:(NSString *)name action:(SEL)action {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name
                                                   target:self
                                                      set:NULL
                                                      get:NULL
                                                   detail:NULL
                                                     cell:PSButtonCell
                                                     edit:NULL];
    s->action = action;
    [s setProperty:@YES forKey:@"enabled"];
    return s;
}

@end
