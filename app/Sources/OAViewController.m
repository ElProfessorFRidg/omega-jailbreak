#import "OAViewController.h"
#import <WebKit/WebKit.h>

static NSString *const kPanelURL = @"http://127.0.0.1:8472/";

@interface OAViewController () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation OAViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.051 blue:0.063 alpha:1.0];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.webView];

    self.statusLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    self.statusLabel.font = [UIFont systemFontOfSize:15];
    self.statusLabel.text = @"Omega\n\nConnexion au panneau…";
    [self.view addSubview:self.statusLabel];

    [self reload];
}

- (void)reload {
    self.statusLabel.hidden = NO;
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:kPanelURL]]];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.statusLabel.hidden = YES;
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.statusLabel.hidden = NO;
    self.statusLabel.text = @"Omega\n\nPanneau injoignable sur 127.0.0.1:8472.\nLe tweak Omega On-Device est-il installé et actif ?\n\nTouchez pour réessayer.";
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)];
    [self.statusLabel setUserInteractionEnabled:YES];
    [self.statusLabel addGestureRecognizer:tap];
}

@end
