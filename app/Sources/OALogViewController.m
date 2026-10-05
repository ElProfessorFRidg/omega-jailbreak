#import "OALogViewController.h"
#import "OABridge.h"
#import "OATheme.h"

@interface OALogViewController ()
@property (nonatomic, strong) UITextView *console;
@end

@implementation OALogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Log";
    self.view.backgroundColor = [OATheme bg];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self action:@selector(reload)];

    self.console = [OATheme console];
    [self.view addSubview:self.console];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.console.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
        [self.console.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.console.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.console.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
    ]];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }

- (void)reload {
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *log = [OABridge readLog];
        dispatch_async(dispatch_get_main_queue(), ^{
            ws.console.text = log;
            NSUInteger len = ws.console.text.length;
            if (len > 1) [ws.console scrollRangeToVisible:NSMakeRange(len - 1, 1)];
        });
    });
}

@end
