#import "OAAppDelegate.h"
#import "OABridge.h"
#import "OATheme.h"
#import "OADashboardViewController.h"
#import "OAModulesViewController.h"
#import "OADNSViewController.h"
#import "OASettingsViewController.h"
#import "OALogViewController.h"

@implementation OAAppDelegate

static UINavigationController *Wrap(UIViewController *vc, NSString *symbol) {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.prefersLargeTitles = YES;
    UIImage *img = [UIImage systemImageNamed:symbol];
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:vc.title image:img tag:0];
    return nav;
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // Global dark appearance.
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *nba = [[UINavigationBarAppearance alloc] init];
        [nba configureWithOpaqueBackground];
        nba.backgroundColor = [OATheme bg];
        nba.titleTextAttributes = @{ NSForegroundColorAttributeName: [OATheme text] };
        nba.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: [OATheme text] };
        UINavigationBar.appearance.standardAppearance = nba;
        UINavigationBar.appearance.scrollEdgeAppearance = nba;
        UINavigationBar.appearance.tintColor = [OATheme accent];

        UITabBarAppearance *tba = [[UITabBarAppearance alloc] init];
        [tba configureWithOpaqueBackground];
        tba.backgroundColor = [OATheme card];
        UITabBar.appearance.standardAppearance = tba;
        if (@available(iOS 15.0, *)) UITabBar.appearance.scrollEdgeAppearance = tba;
        UITabBar.appearance.tintColor = [OATheme accent];
        UITabBar.appearance.unselectedItemTintColor = [OATheme subtext];
    }

    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = @[
        Wrap([[OADashboardViewController alloc] init], @"shield.lefthalf.filled"),
        Wrap([[OAModulesViewController alloc] init],   @"slider.horizontal.3"),
        Wrap([[OADNSViewController alloc] init],        @"network"),
        Wrap([[OASettingsViewController alloc] init],   @"gearshape"),
        Wrap([[OALogViewController alloc] init],        @"doc.plaintext"),
    ];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = tabs;
    if (@available(iOS 13.0, *)) self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self.window makeKeyAndVisible];

    // Optional: apply on launch if the user enabled it.
    if ([OABridge boolForKey:@"auto_apply" fallback:NO]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [OABridge runCommand:@"apply" timeout:20];
        });
    }
    return YES;
}

@end
