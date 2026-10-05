#import "OADNSViewController.h"
#import "OABridge.h"
#import "OATheme.h"

@interface OADNSViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *upstream;
@property (nonatomic, strong) UITextView *console;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@end

@implementation OADNSViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DNS local";
    self.view.backgroundColor = [OATheme bg];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:g.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
    ]];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.layoutMargins = UIEdgeInsetsMake(16, 16, 24, 16);
    stack.layoutMarginsRelativeArrangement = YES;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
    ]];

    // explanation card
    UIView *card = [OATheme card:nil];
    [stack addArrangedSubview:card];
    UILabel *info = [[UILabel alloc] init];
    info.translatesAutoresizingMaskIntoConstraints = NO;
    info.numberOfLines = 0;
    info.textColor = [OATheme subtext];
    info.font = [UIFont systemFontOfSize:13];
    info.text = @"Installe un résolveur DNS local (dnsmasq @ 127.0.0.1) qui bloque "
                 "ocsp/ppq/crl/valid.apple.com et transmet le reste à l'upstream. "
                 "Puis installe le profil généré pour router iOS vers 127.0.0.1.\n\n"
                 "Nécessite le paquet dnsmasq (Procursus).";
    [card addSubview:info];
    [NSLayoutConstraint activateConstraints:@[
        [info.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [info.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [info.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [info.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
    ]];

    // upstream field
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = @"Upstream DNS";
    lbl.textColor = [OATheme subtext];
    lbl.font = [UIFont systemFontOfSize:13];
    [stack addArrangedSubview:lbl];

    self.upstream = [[UITextField alloc] init];
    self.upstream.translatesAutoresizingMaskIntoConstraints = NO;
    self.upstream.text = [OABridge stringForKey:@"dns_upstream" fallback:@"1.1.1.1"];
    self.upstream.placeholder = @"1.1.1.1";
    self.upstream.textColor = [OATheme text];
    self.upstream.font = [OATheme mono:15];
    self.upstream.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.upstream.autocorrectionType = UITextAutocorrectionTypeNo;
    self.upstream.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.upstream.backgroundColor = [OATheme card];
    self.upstream.borderStyle = UITextBorderStyleRoundedRect;
    self.upstream.delegate = self;
    [self.upstream.heightAnchor constraintEqualToConstant:44].active = YES;
    [stack addArrangedSubview:self.upstream];

    // buttons
    UIButton *install = [OATheme button:@"Installer le DNS local" color:[OATheme green]];
    [install addTarget:self action:@selector(install) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:install];

    UIButton *profile = [OATheme button:@"Installer le profil (127.0.0.1)" color:[OATheme blue]];
    [profile addTarget:self action:@selector(installProfile) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:profile];

    UIButton *status = [OATheme button:@"État du DNS" color:[OATheme purple]];
    [status addTarget:self action:@selector(status) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:status];

    UIButton *remove = [OATheme button:@"Retirer le DNS local" color:[OATheme accent]];
    [remove addTarget:self action:@selector(remove) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:remove];
    self.buttons = @[install, profile, status, remove];

    self.console = [OATheme console];
    [stack addArrangedSubview:self.console];
    [self.console.heightAnchor constraintEqualToConstant:240].active = YES;
    self.console.text = @"Prêt.";

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    self.spinner.color = [OATheme subtext];
    [self.view addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-16],
    ]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}
- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSString *v = [textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (v.length) [OABridge setString:v forKey:@"dns_upstream"];
}

- (void)setBusy:(BOOL)busy {
    for (UIButton *b in self.buttons) { b.enabled = !busy; b.alpha = busy ? 0.5 : 1.0; }
    if (busy) [self.spinner startAnimating]; else [self.spinner stopAnimating];
}

- (void)run:(NSString *)cmd timeout:(NSTimeInterval)t {
    [self.upstream resignFirstResponder];
    self.console.text = [NSString stringWithFormat:@"%@\n…", cmd];
    [self setBusy:YES];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [OABridge runCommand:cmd timeout:t];
        dispatch_async(dispatch_get_main_queue(), ^{
            ws.console.text = out;
            [ws setBusy:NO];
        });
    });
}

- (void)install {
    NSString *up = [self.upstream.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (up.length == 0) up = @"1.1.1.1";
    [OABridge setString:up forKey:@"dns_upstream"];
    [self run:[NSString stringWithFormat:@"dns-install %@", up] timeout:30];
}

- (void)status { [self run:@"dns-status" timeout:20]; }
- (void)remove { [self run:@"dns-remove" timeout:20]; }

// Present the generated .mobileconfig via a share sheet so the user can open
// it in Settings / Safari to install it. iOS has no public API to install a
// profile silently, so this hands it to the system UI.
- (void)installProfile {
    NSURL *url = [NSURL fileURLWithPath:kOmegaProfile];
    if (![NSFileManager.defaultManager fileExistsAtPath:kOmegaProfile]) {
        self.console.text = @"Profil introuvable. Lance d'abord « Installer le DNS local ».";
        return;
    }
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    av.popoverPresentationController.sourceView = self.view;
    av.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:av animated:YES completion:nil];
}

@end
