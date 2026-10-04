#import "OAViewController.h"
#import <spawn.h>
#import <sys/wait.h>
#import <objc/runtime.h>

extern char **environ;
static NSString *const kWorker = @"/var/jb/usr/local/bin/omega-ondevice";

@interface OAViewController ()
@property (nonatomic, strong) UITextView *output;
@property (nonatomic, strong) UILabel *header;
@end

@implementation OAViewController

// Run a program with args, capture stdout+stderr, return combined output.
static NSString *runProgram(NSString *path, NSArray<NSString *> *args) {
    int outPipe[2];
    if (pipe(outPipe) != 0) return @"pipe() failed";

    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&fa, outPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&fa, outPipe[0]);
    posix_spawn_file_actions_addclose(&fa, outPipe[1]);

    NSMutableArray *all = [NSMutableArray arrayWithObject:path];
    [all addObjectsFromArray:args];
    char **argv = calloc(all.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < all.count; i++) argv[i] = strdup([all[i] UTF8String]);
    argv[all.count] = NULL;

    pid_t pid = 0;
    int rc = posix_spawn(&pid, [path UTF8String], &fa, NULL, argv, environ);
    close(outPipe[1]);
    for (NSUInteger i = 0; i < all.count; i++) free(argv[i]);
    free(argv);
    posix_spawn_file_actions_destroy(&fa);

    if (rc != 0) {
        close(outPipe[0]);
        return [NSString stringWithFormat:@"could not launch %@ (err %d). Is Omega On-Device installed?", path, rc];
    }

    NSMutableData *buf = [NSMutableData data];
    char chunk[4096];
    ssize_t n;
    while ((n = read(outPipe[0], chunk, sizeof(chunk))) > 0) [buf appendBytes:chunk length:n];
    close(outPipe[0]);
    int status = 0; waitpid(pid, &status, 0);

    NSString *s = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
    return s.length ? s : [NSString stringWithFormat:@"(no output, exit %d)", WEXITSTATUS(status)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIColor *bg = [UIColor colorWithRed:0.043 green:0.051 blue:0.063 alpha:1.0];
    self.view.backgroundColor = bg;

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
        b.tag = i;
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
                        "• Appliquer : vide ocspcache + verrouille les 4 ban-lists (schg)\n"
                        "• Vérifier / Log / Debug : état réel sur l'appareil\n\n"
                        "Rappel : en ligne, bloque ocsp/ppq/crl/valid.apple.com au DNS.";
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
    self.output.text = [NSString stringWithFormat:@"$ omega-ondevice %@\n…", cmd];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *result;
        if ([cmd isEqualToString:@"log"]) {
            NSString *log = [NSString stringWithContentsOfFile:@"/var/mobile/omega-ondevice.log"
                                                      encoding:NSUTF8StringEncoding error:nil];
            result = log.length ? log : @"(log vide)";
        } else {
            result = runProgram(kWorker, @[cmd]);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.output.text = [NSString stringWithFormat:@"$ omega-ondevice %@\n\n%@", cmd, result];
        });
    });
}

@end
