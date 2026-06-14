#import <UIKit/UIKit.h>

// Sets the same orientations on a batch of apps at once (and enables them). Pushed from
// the multi-select mode of ARAppsTableController.
@interface ARBulkOrientationController : UITableViewController
- (instancetype)initWithBundleIDs:(NSArray<NSString *> *)bundleIDs;
@property (nonatomic, copy) void (^onDone)(void);
@end
