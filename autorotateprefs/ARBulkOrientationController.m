#import "ARBulkOrientationController.h"
#import "ARStore.h"

static const NSInteger kEnabledTag = 100;

@interface ARBulkOrientationController ()
@property (nonatomic, copy) NSArray<NSString *> *bundleIDs;
@property (nonatomic, copy) NSArray<NSString *> *titles;   // orientation row labels
@property (nonatomic, copy) NSArray<NSString *> *suffixes; // matching pref suffixes
@property (nonatomic, strong) NSMutableArray<NSNumber *> *states; // BOOL per orientation
@property (nonatomic) BOOL enabledState;                   // turn the apps on/off
@end

@implementation ARBulkOrientationController

- (instancetype)initWithBundleIDs:(NSArray<NSString *> *)bundleIDs {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _bundleIDs = [bundleIDs copy];
        _titles    = @[@"Portrait", @"Portrait upside down", @"Landscape left", @"Landscape right"];
        _suffixes  = @[@"Portrait", @"UpsideDown", @"LandscapeLeft", @"LandscapeRight"];
        _states    = [@[@NO, @NO, @NO, @NO] mutableCopy];
        _enabledState = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"%lu apps", (unsigned long)self.bundleIDs.count];
}

// Sections: 0 = Enabled switch, 1 = Orientations, 2 = apply button.
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return (NSInteger)self.titles.count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? @"Orientations" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Turn the selected apps on or off.";
    if (section == 1) return @"Tick one for a hard lock, or several to allow rotation only among them. "
                             @"Applying overwrites each selected app's orientations.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 || indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sw"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sw"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = [[UISwitch alloc] init];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        if (indexPath.section == 0) {
            cell.textLabel.text = @"Enabled";
            sw.tag = kEnabledTag;
            sw.on = self.enabledState;
        } else {
            cell.textLabel.text = self.titles[indexPath.row];
            cell.textLabel.enabled = self.enabledState;
            sw.tag = indexPath.row;
            sw.on = self.states[indexPath.row].boolValue;
            sw.enabled = self.enabledState;   // orientations only matter when enabling
        }
        cell.accessoryView = sw;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"apply"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"apply"];
    cell.textLabel.text = [NSString stringWithFormat:@"Set on %lu apps", (unsigned long)self.bundleIDs.count];
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.accessoryView = nil;
    return cell;
}

- (void)switchChanged:(UISwitch *)sw {
    if (sw.tag == kEnabledTag) {
        self.enabledState = sw.isOn;
        // Re-render so the orientation rows grey out / enable to match.
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    } else {
        self.states[sw.tag] = @(sw.isOn);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2) return;

    for (NSString *bid in self.bundleIDs) {
        [ARStore setAppEnabled:self.enabledState forBundle:bid];
        for (NSUInteger i = 0; i < self.suffixes.count; i++)
            [ARStore setBool:self.states[i].boolValue forKey:[ARStore orientationKey:bid suffix:self.suffixes[i]]];
    }
    if (self.onDone) self.onDone();
    [self.navigationController popViewControllerAnimated:YES];
}

@end
