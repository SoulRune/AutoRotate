#import "ARStore.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <spawn.h>

static NSString *const kDraftDomain   = @"com.i0stweak3r-sr.autorotate";
static NSString *const kAppliedDomain = @"com.i0stweak3r-sr.autorotate.applied";
static NSString *const kAppliedNotify = @"com.i0stweak3r-sr.autorotate/applied";

// Minimal private API surface for enumerating installed apps.
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;   // "User" / "System" / ...
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allApplications;
@end

@interface ALApplicationList : NSObject
+ (instancetype)sharedApplicationList;
- (NSDictionary *)applicationsFilteredUsingPredicate:(NSPredicate *)predicate
                                         onlyVisible:(BOOL)onlyVisible
                              titleSortedIdentifiers:(NSArray **)outIdentifiers;
- (UIImage *)iconOfSize:(int)iconSize forDisplayIdentifier:(NSString *)displayIdentifier;
@end

@implementation ARStore

#pragma mark - Paths

+ (NSString *)pathForDomain:(NSString *)domain {
    NSString *root = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"/var/jb" : @"";
    return [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/%@.plist", root, domain];
}
+ (NSString *)draftPath   { return [self pathForDomain:kDraftDomain]; }
+ (NSString *)appliedPath { return [self pathForDomain:kAppliedDomain]; }

#pragma mark - Draft access

+ (NSMutableDictionary *)draft {
    return [NSMutableDictionary dictionaryWithContentsOfFile:[self draftPath]] ?: [NSMutableDictionary dictionary];
}

+ (BOOL)boolForKey:(NSString *)key {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self draftPath]];
    return [d[key] boolValue];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    NSString *path = [self draftPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableDictionary *d = [self draft];
    d[key] = @(value);
    [d writeToFile:path atomically:YES];
}

+ (NSString *)enableKey:(NSString *)bid { return [@"enabled-" stringByAppendingString:bid]; }
+ (NSString *)orientationKey:(NSString *)bid suffix:(NSString *)suffix {
    return [NSString stringWithFormat:@"%@-%@", bid, suffix];
}
+ (BOOL)appEnabled:(NSString *)bid { return [self boolForKey:[self enableKey:bid]]; }
+ (void)setAppEnabled:(BOOL)value forBundle:(NSString *)bid { [self setBool:value forKey:[self enableKey:bid]]; }

#pragma mark - App enumeration

+ (NSArray<NSDictionary *> *)appsForSystem:(BOOL)system {
    // Classify every installed app by type, and (when AppList is present) restrict to the
    // visible set so the System list isn't flooded with internal/hidden bundles.
    LSApplicationWorkspace *ws = [objc_getClass("LSApplicationWorkspace") defaultWorkspace];
    NSMutableDictionary<NSString *, NSString *> *typeOf = [NSMutableDictionary dictionary]; // bid -> type
    NSMutableDictionary<NSString *, NSString *> *nameOf = [NSMutableDictionary dictionary]; // bid -> name
    for (LSApplicationProxy *app in [ws allApplications]) {
        NSString *bid = app.applicationIdentifier;
        if (!bid.length) continue;
        typeOf[bid] = app.applicationType ?: @"System";
        nameOf[bid] = app.localizedName ?: bid;
    }

    NSArray *candidateIds = nil;
    ALApplicationList *al = [objc_getClass("ALApplicationList") sharedApplicationList];
    SEL sel = @selector(applicationsFilteredUsingPredicate:onlyVisible:titleSortedIdentifiers:);
    if ([al respondsToSelector:sel]) {
        @try {
            NSArray *sortedIds = nil;
            NSDictionary *apps = [al applicationsFilteredUsingPredicate:[NSPredicate predicateWithValue:YES]
                                                            onlyVisible:YES
                                                 titleSortedIdentifiers:&sortedIds];
            candidateIds = sortedIds.count ? sortedIds : apps.allKeys;
            for (NSString *bid in apps) if (!nameOf[bid]) nameOf[bid] = apps[bid] ?: bid;
        } @catch (__unused NSException *e) {}
    }
    if (candidateIds.count == 0) candidateIds = typeOf.allKeys; // no AppList -> everything

    NSMutableArray *result = [NSMutableArray array];
    for (NSString *bid in candidateIds) {
        NSString *type = typeOf[bid];
        BOOL isSystem = ![type isEqualToString:@"User"]; // treat non-User as system
        if (isSystem != system) continue;
        [result addObject:@{ @"id": bid, @"name": nameOf[bid] ?: bid }];
    }
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];

    // SpringBoard isn't a listed application, so add the system-UI surfaces explicitly at
    // the top. They use the same orientation model as apps (the tweak reads the same keys
    // by bundle id) but need their own SpringBoard hooks to actually rotate.
    if (system) {
        [result insertObject:@{ @"id": @"com.apple.springboard", @"name": @"Home & Lock Screen (beta)" } atIndex:0];
    }
    return result;
}

#pragma mark - Icons

+ (UIImage *)iconForBundle:(NSString *)bid {
    if (!bid.length) return nil;
    // 1) AppList (ALApplicationIconSizeSmall == 29).
    ALApplicationList *al = [objc_getClass("ALApplicationList") sharedApplicationList];
    if ([al respondsToSelector:@selector(iconOfSize:forDisplayIdentifier:)]) {
        @try {
            UIImage *img = [al iconOfSize:29 forDisplayIdentifier:bid];
            if (img) return img;
        } @catch (__unused NSException *e) {}
    }
    // 2) Private UIImage app-icon API (format 2 == small). Reached via objc_msgSend so the
    //    symbol isn't named (and to avoid availability noise).
    SEL s = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if ([UIImage respondsToSelector:s]) {
        CGFloat scale = [UIScreen mainScreen].scale;
        UIImage *img = ((UIImage *(*)(id, SEL, NSString *, int, CGFloat))objc_msgSend)([UIImage class], s, bid, 2, scale);
        if (img) return img;
    }
    return nil;
}

#pragma mark - Commit / reset / respring

+ (void)apply {
    NSDictionary *draft = [NSDictionary dictionaryWithContentsOfFile:[self draftPath]] ?: @{};
    [draft writeToFile:[self appliedPath] atomically:YES];
    notify_post(kAppliedNotify.UTF8String);
}

+ (void)resetAll {
    [[NSFileManager defaultManager] removeItemAtPath:[self draftPath] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[self appliedPath] error:nil];
    notify_post(kAppliedNotify.UTF8String);
}

+ (void)respring {
    pid_t pid;
    const char *jb = "/var/jb/usr/bin/killall";
    const char *path = [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:jb]] ? jb : "/usr/bin/killall";
    const char *args[] = { "killall", "-9", "SpringBoard", NULL };
    posix_spawn(&pid, path, NULL, NULL, (char *const *)args, NULL);
}

@end
