#import "OADashboardViewController.h"
#import "OABridge.h"
#import "OATheme.h"

@interface OADashboardViewController ()
@property (nonatomic, strong) UILabel *statusDot;
@property (nonatomic, strong) UILabel *statusLine;
@property (nonatomic, strong) UILabel *modulesLine;
@property (nonatomic, strong) UITextView *console;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *applyBtn;
@end

@implementation OADashboardViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Omega";
    self.view.backgroundColor = [OATheme bg];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
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
    stack.spacing = 16;
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

    // --- status card ---
    UIView *card = [OATheme card:nil];
    [stack addArrangedSubview:card];

    self.statusDot = [[UILabel alloc] init];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDot.text = @"●";
    self.statusDot.textColor = [OATheme subtext];
    self.statusDot.font = [UIFont systemFontOfSize:22];

    self.statusLine = [[UILabel alloc] init];
    self.statusLine.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLine.text = @"État inconnu";
    self.statusLine.textColor = [OATheme text];
    self.statusLine.font = [UIFont boldSystemFontOfSize:18];

    self.modulesLine = [[UILabel alloc] init];
    self.modulesLine.translatesAutoresizingMaskIntoConstraints = NO;
    self.modulesLine.text = @"Modules : …";
    self.modulesLine.textColor = [OATheme subtext];
    self.modulesLine.font = [UIFont systemFontOfSize:13];
    self.modulesLine.numberOfLines = 0;

    [card addSubview:self.statusDot];
    [card addSubview:self.statusLine];
    [card addSubview:self.modulesLine];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusDot.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [self.statusDot.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.statusLine.centerYAnchor constraintEqualToAnchor:self.statusDot.centerYAnchor],
        [self.statusLine.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:10],
        [self.statusLine.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.modulesLine.topAnchor constraintEqualToAnchor:self.statusDot.bottomAnchor constant:10],
        [self.modulesLine.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.modulesLine.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.modulesLine.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];

    // --- actions ---
    self.applyBtn = [OATheme button:@"Appliquer maintenant" color:[OATheme accent]];
    [self.applyBtn addTarget:self action:@selector(apply) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.applyBtn];

    UIButton *refresh = [OATheme button:@"Rafraîchir l'état" color:[OATheme blue]];
    [refresh addTarget:self action:@selector(refresh) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:refresh];

    // --- console ---
    self.console = [OATheme console];
    [stack addArrangedSubview:self.console];
    [self.console.heightAnchor constraintEqualToConstant:260].active = YES;
    self.console.text = @"Omega — neutralise la révocation locale.\n\n"
                         "• Appliquer : exécute les modules activés (onglet Modules), via root.\n"
                         "• DNS : installe un résolveur local bloquant ocsp/ppq/crl/valid.apple.com.\n\n"
                         "Astuce : hors-ligne, la neutralisation locale suffit ; en ligne, active le DNS.";

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    self.spinner.color = [OATheme subtext];
    [card addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.statusDot.centerYAnchor],
        [self.spinner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)setBusy:(BOOL)busy {
    self.applyBtn.enabled = !busy;
    self.applyBtn.alpha = busy ? 0.5 : 1.0;
    if (busy) [self.spinner startAnimating]; else [self.spinner stopAnimating];
}

- (void)refresh {
    [self setBusy:YES];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [OABridge runCommand:@"status" timeout:15];
        dispatch_async(dispatch_get_main_queue(), ^{
            [ws applyStatusText:out];
            [ws setBusy:NO];
        });
    });
}

- (void)apply {
    self.console.text = @"omega-ondevice apply\n…";
    [self setBusy:YES];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [OABridge runCommand:@"apply" timeout:20];
        dispatch_async(dispatch_get_main_queue(), ^{
            ws.console.text = [NSString stringWithFormat:@"omega-ondevice apply\n\n%@", out];
            [ws setBusy:NO];
            [ws refresh];
        });
    });
}

// Parse the worker's `status` output into the coloured summary + console.
- (void)applyStatusText:(NSString *)out {
    self.console.text = out;

    BOOL locked = ([out containsString:@"immutable=schg"]);
    BOOL writable = ([out containsString:@"immutable=no"]);
    if (locked && !writable) {
        self.statusDot.textColor = [OATheme green];
        self.statusLine.text = @"Protégé (ban-lists verrouillées)";
    } else if (locked && writable) {
        self.statusDot.textColor = [OATheme amber];
        self.statusLine.text = @"Partiel — certaines cibles non verrouillées";
    } else {
        self.statusDot.textColor = [OATheme accent];
        self.statusLine.text = @"Non appliqué";
    }

    NSMutableArray *on = [NSMutableArray array];
    NSDictionary *mods = @{ @"mod_ocsp": @"OCSP", @"mod_banlists": @"Ban-lists",
                            @"mod_valid": @"valid.sqlite3", @"mod_restart": @"Restart" };
    for (NSString *k in @[@"mod_ocsp", @"mod_banlists", @"mod_valid", @"mod_restart"]) {
        if ([OABridge boolForKey:k fallback:[k isEqualToString:@"mod_valid"] ? NO : YES]) [on addObject:mods[k]];
    }
    self.modulesLine.text = [NSString stringWithFormat:@"Modules actifs : %@",
                             on.count ? [on componentsJoinedByString:@" · "] : @"aucun"];
}

@end
