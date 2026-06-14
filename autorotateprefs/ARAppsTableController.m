#import "ARAppsTableController.h"
#import "ARBulkOrientationController.h"
#import "ARAppListController.h"
#import "ARStore.h"
#import <Preferences/PSSpecifier.h>

@interface ARAppsTableController () <UISearchResultsUpdating>
@property (nonatomic) BOOL system;
@property (nonatomic, strong) NSArray<NSDictionary *> *allApps;
@property (nonatomic, strong) NSArray<NSDictionary *> *enabledApps;
@property (nonatomic, strong) NSArray<NSDictionary *> *disabledApps;
@property (nonatomic, copy)   NSString *filter;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) NSMutableSet<NSString *> *selected;
@end

@implementation ARAppsTableController

- (instancetype)initWithSystem:(BOOL)system {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _system = system;
        _selected = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.system ? @"System Apps" : @"User Apps";
    self.allApps = [ARStore appsForSystem:self.system];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Search name or bundle id";
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.tableView.rowHeight = 46.0;   // compact rows
    [self updateBars];
    [self recompute];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self recompute];                 // reflect changes made on a detail page
    self.navigationController.toolbarHidden = !self.tableView.isEditing;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.toolbarHidden = YES;
}

#pragma mark - Data

- (void)recompute {
    NSArray *apps = self.allApps;
    NSString *f = self.filter.lowercaseString;
    if (f.length) {
        apps = [apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *b) {
            return [[app[@"name"] lowercaseString] containsString:f] || [[app[@"id"] lowercaseString] containsString:f];
        }]];
    }
    NSMutableArray *en = [NSMutableArray array], *dis = [NSMutableArray array];
    for (NSDictionary *app in apps) [([ARStore appEnabled:app[@"id"]] ? en : dis) addObject:app];
    self.enabledApps = en;
    self.disabledApps = dis;
    [self.tableView reloadData];
}

- (NSDictionary *)appAt:(NSIndexPath *)ip {
    return ip.section == 0 ? self.enabledApps[ip.row] : self.disabledApps[ip.row];
}

// App icon scaled to a fixed square so it doesn't inflate the row height.
- (UIImage *)iconAt:(CGFloat)side forBundle:(NSString *)bid {
    UIImage *img = [ARStore iconForBundle:bid];
    if (!img) return nil;
    CGSize size = CGSizeMake(side, side);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [img drawInRect:CGRectMake(0, 0, side, side)];
    }];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.filter = searchController.searchBar.text;
    [self recompute];
}

#pragma mark - Bars

- (void)updateBars {
    BOOL editing = self.tableView.isEditing;
    if (editing) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(exitSelect)];
        UIBarButtonItem *setBtn = [[UIBarButtonItem alloc] initWithTitle:@"Set Orientations" style:UIBarButtonItemStylePlain target:self action:@selector(setOrientationsForSelection)];
        setBtn.enabled = self.selected.count > 0;
        UIBarButtonItem *all = [[UIBarButtonItem alloc] initWithTitle:@"Select All" style:UIBarButtonItemStylePlain target:self action:@selector(selectAll)];
        UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        self.toolbarItems = @[setBtn, flex, all];
    } else {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Select" style:UIBarButtonItemStylePlain target:self action:@selector(enterSelect)];
        self.toolbarItems = nil;
    }
    // Apply lives only in the main menu; the toolbar here is just for multi-select.
    self.navigationController.toolbarHidden = !editing;
}

- (void)enterSelect {
    [self.selected removeAllObjects];
    [self setEditing:YES animated:YES];
    [self.tableView reloadData];
    [self updateBars];
}

- (void)exitSelect {
    [self setEditing:NO animated:YES];
    [self.selected removeAllObjects];
    [self.tableView reloadData];
    [self updateBars];
}

- (void)selectAll {
    for (NSDictionary *app in self.enabledApps)  [self.selected addObject:app[@"id"]];
    for (NSDictionary *app in self.disabledApps) [self.selected addObject:app[@"id"]];
    for (NSInteger s = 0; s < 2; s++) {
        NSInteger rows = [self tableView:self.tableView numberOfRowsInSection:s];
        for (NSInteger r = 0; r < rows; r++)
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:s] animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self updateBars];
}

- (void)setOrientationsForSelection {
    if (self.selected.count == 0) return;
    ARBulkOrientationController *vc = [[ARBulkOrientationController alloc] initWithBundleIDs:self.selected.allObjects];
    __weak typeof(self) weakSelf = self;
    vc.onDone = ^{ [weakSelf exitSelect]; [weakSelf recompute]; };
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.enabledApps.count : self.disabledApps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? [NSString stringWithFormat:@"Enabled (%lu)", (unsigned long)self.enabledApps.count]
                        : [NSString stringWithFormat:@"Disabled (%lu)", (unsigned long)self.disabledApps.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    NSDictionary *app = [self appAt:indexPath];
    cell.textLabel.text = app[@"name"];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0];
    cell.detailTextLabel.text = app[@"id"];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.imageView.image = [self iconAt:30.0 forBundle:app[@"id"]];
    cell.imageView.layer.cornerRadius = 6.0;
    cell.imageView.clipsToBounds = YES;
    cell.accessoryType = self.tableView.isEditing ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *app = [self appAt:indexPath];
    if (self.tableView.isEditing) {
        [self.selected addObject:app[@"id"]];
        [self updateBars];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:app[@"name"] target:nil set:NULL get:NULL detail:Nil cell:PSLinkCell edit:Nil];
    [spec setProperty:app[@"id"] forKey:@"bid"];
    ARAppListController *vc = [[ARAppListController alloc] init];
    [vc setSpecifier:spec];
    vc.title = app[@"name"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.tableView.isEditing) {
        [self.selected removeObject:[self appAt:indexPath][@"id"]];
        [self updateBars];
    }
}

// Trailing (swipe-left) quick enable/disable toggle.
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *app = [self appAt:indexPath];
    NSString *bid = app[@"id"];
    BOOL enabled = [ARStore appEnabled:bid];
    UIContextualAction *act = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                      title:(enabled ? @"Disable" : @"Enable")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ARStore setAppEnabled:!enabled forBundle:bid];
        done(YES);
        [self recompute];
    }];
    act.backgroundColor = enabled ? [UIColor systemRedColor] : [UIColor systemGreenColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[act]];
}

@end
