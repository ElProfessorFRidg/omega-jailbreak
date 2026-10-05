#import "OAModulesViewController.h"
#import "OABridge.h"
#import "OATheme.h"

@interface OAModulesViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *modules;
@end

@implementation OAModulesViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = @"Modules";
        self.modules = @[
            @{ @"key": @"mod_ocsp", @"def": @YES, @"title": @"Purge du cache OCSP",
               @"sub": @"Vide ocspcache.sqlite3 et le verrouille (schg)." },
            @{ @"key": @"mod_banlists", @"def": @YES, @"title": @"Ban-lists vides + verrou",
               @"sub": @"Réécrit les 4 listes MobileIdentityData vides et immuables." },
            @{ @"key": @"mod_valid", @"def": @NO, @"title": @"Blanchir valid.sqlite3",
               @"sub": @"Agressif : purge la base Valid de trustd. Laisse OFF si incertain." },
            @{ @"key": @"mod_restart", @"def": @YES, @"title": @"Redémarrer les services",
               @"sub": @"Relance trustd/amfid/installd/misagentd après application." },
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [OATheme bg];
    self.tableView.backgroundColor = [OATheme bg];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Appliquer"
                                         style:UIBarButtonItemStyleDone
                                        target:self action:@selector(apply)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.modules.count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Techniques appliquées par « Appliquer »";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Chaque module est indépendant. Les réglages sont lus par le worker root à chaque exécution (et au boot).";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"m"];
    NSDictionary *m = self.modules[indexPath.row];
    cell.backgroundColor = [OATheme card];
    cell.textLabel.text = m[@"title"];
    cell.textLabel.textColor = [OATheme text];
    cell.detailTextLabel.text = m[@"sub"];
    cell.detailTextLabel.textColor = [OATheme subtext];
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.onTintColor = [OATheme green];
    sw.tag = indexPath.row;
    sw.on = [OABridge boolForKey:m[@"key"] fallback:[m[@"def"] boolValue]];
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)toggle:(UISwitch *)sw {
    NSDictionary *m = self.modules[sw.tag];
    [OABridge setBool:sw.on forKey:m[@"key"]];
}

- (void)apply {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Application…"
                                                               message:@"\n\n"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:ac animated:YES completion:nil];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [OABridge runCommand:@"apply" timeout:20];
        dispatch_async(dispatch_get_main_queue(), ^{
            [ac dismissViewControllerAnimated:YES completion:^{
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Résultat"
                                                                             message:out
                                                                      preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [ws presentViewController:done animated:YES completion:nil];
            }];
        });
    });
}

@end
