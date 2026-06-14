#import <UIKit/UIKit.h>

// One app category page (User or System): icons, Enabled/Disabled sections, search,
// swipe-to-toggle, and a multi-select mode for setting orientations in bulk.
@interface ARAppsTableController : UITableViewController
- (instancetype)initWithSystem:(BOOL)system;
@end
