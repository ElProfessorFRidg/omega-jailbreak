#import "OAViewController.h"
#import <objc/runtime.h>

// Shared trigger dir watched by the root daemon (party.jailbreak.omega.trigger).
static NSString *const kDir = @"/var/mobile/.omega";
static NSString *const kLog = @"/var/mobile/omega-ondevice.log";

@interface OAViewController ()
@property (nonatomic, strong) UITextView *output;
@property (nonatomic, strong) UILabel *header;
@end

@implementation OAViewController

// Ask the root daemon to run a subcommand and return its output.
static NSString *runViaRoot(NSString *cmd) {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:kDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *cmdF = [kDir stringByAppendingPathComponent:@"cmd"];
    NSString *outF = [kDir stringByAppendingPathComponent:@"out"];
    NSString *trgF = [kDir stringByAppendingPathComponent:@"trigger"];

    NSError *e = nil;
    if (![cmd writeToFile:cmdF atomically:YES encoding:NSUTF8StringEncoding error:&e]) {
        return [NSString stringWithFormat:
            @"Impossible d'écrire %@\n%@\n\nL'app n'a pas accès à /var/mobile (sandbox ?).",
            cmdF, e.localizedDescription];
    }
    NSDate *prev = [[fm attributesOfItemAtPath:outF error:nil] fileModificationDate];

    NSString *nonce = [NSString stringWithFormat:@"%f", NSDate.date.timeIntervalSince1970];
    if (![nonce writeToFile:trgF atomically:YES encoding:NSUTF8StringEncoding error:&e]) {
        return [NSString stringWithFormat:@"Impossible de déclencher le démon : %@", e.localizedDescription];
    }

    for (int i = 0; i < 75; i++) {            // up to ~15 s
        usleep(200000);
        NSDate *now = [[fm attributesOfItemAtPath:outF error:nil] fileModificationDate];
        if (now && (!prev || [now compare:prev] == NSOrderedDescending)) {
            NSString *s = [NSString stringWithContentsOfFile:outF encoding:NSUTF8StringEncoding error:nil];
            return s.length ? s : @"(réponse vide)";
        }
    }
    return @"Pas de réponse du démon root.\n\nLe paquet 'Omega On-Device' est-il "
           @"installé et le démon party.jailbreak.omega.trigger chargé ? "
           @"Fais un respring puis réessaie.";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.051 blue:0.063 alpha:1.0];

    self.header = [[UILabel alloc] init];
    self.header.translatesAutoresizingMaskIntoConstraints = NO;
    self.header.text = @"Omega";
    self.header.textColor = [UIColor whiteColor];
    self.header.font = [UIFont boldSystemFontOfSize:26];
    [self.view addSubview:self.header];

    NSArray *titles = @[@"Appliquer", @"Vérifier", @"Log", @"Debug"];
    NSArray *cmds   = @[@"apply", @"status", @"log", @"diag"];
    NSArray *colors = @[[UIColor colorWithRed:0.75 green:0.22 blue:0.17 alpha:1],
                        [UIColor colorWithRed:0.18 green:0.49 blue:0.27 alpha:1],
                        [UIColor colorWithRed:0.18 green:0.35 blue:0.67 alpha:1],
                        [UIColor colorWithRed:0.42 green:0.31 blue:0.63 alpha:1]];
    UIStackView *row = [[UIStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 8;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        b.backgroundColor = colors[i];
        b.layer.cornerRadius = 12;
        [b.heightAnchor constraintEqualToConstant:52].active = YES;
        objc_setAssociatedObject(b, "cmd", cmds[i], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:b];
    }
    [self.view addSubview:row];

    self.output = [[UITextView alloc] init];
    self.output.translatesAutoresizingMaskIntoConstraints = NO;
    self.output.editable = NO;
    self.output.backgroundColor = [UIColor colorWithRed:0.02 green:0.027 blue:0.039 alpha:1];
    self.output.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    self.output.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont systemFontOfSize:12];
    self.output.layer.cornerRadius = 12;
    self.output.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    self.output.text = @"Omega — neutralise la révocation locale.\n\n"
                        "• Appliquer : vide ocspcache + verrouille les 4 ban-lists (schg), via root.\n"
                        "• Vérifier / Debug : état réel. Log : journal du worker.\n\n"
                        "En ligne, bloque ocsp/ppq/crl/valid.apple.com au DNS.";
    [self.view addSubview:self.output];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.header.topAnchor constraintEqualToAnchor:g.topAnchor constant:16],
        [self.header.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [row.topAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:14],
        [row.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [row.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.output.topAnchor constraintEqualToAnchor:row.bottomAnchor constant:14],
        [self.output.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.output.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.output.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
    ]];
}

- (void)tap:(UIButton *)sender {
    NSString *cmd = objc_getAssociatedObject(sender, "cmd");
    self.output.text = [NSString stringWithFormat:@"omega-ondevice %@\n…", cmd];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *result;
        if ([cmd isEqualToString:@"log"]) {
            NSString *log = [NSString stringWithContentsOfFile:kLog encoding:NSUTF8StringEncoding error:nil];
            result = log.length ? log : @"(log vide)";
        } else {
            result = runViaRoot(cmd);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.output.text = [NSString stringWithFormat:@"omega-ondevice %@\n\n%@", cmd, result];
        });
    });
}

@end
