#import "OAAppDelegate.h"
#import "OAViewController.h"

@implementation OAAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[OAViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
