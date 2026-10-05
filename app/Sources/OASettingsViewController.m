#import "OASettingsViewController.h"
#import "OABridge.h"
#import "OATheme.h"

@implementation OASettingsViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"Réglages";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [OATheme bg];
    self.tableView.backgroundColor = [OATheme bg];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) { case 0: return 1; case 1: return 2; default: return 3; }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) { case 0: return @"Comportement"; case 1: return @"Diagnostic"; default: return @"À propos"; }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Le worker se ré-applique aussi à chaque démarrage (LaunchDaemon) et toutes les heures.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [OATheme card];
    cell.textLabel.textColor = [OATheme text];
    cell.detailTextLabel.textColor = [OATheme subtext];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (ip.section == 0) {
        cell.textLabel.text = @"Appliquer au lancement";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.onTintColor = [OATheme green];
        sw.on = [OABridge boolForKey:@"auto_apply" fallback:NO];
        [sw addTarget:self action:@selector(toggleAuto:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (ip.section == 1) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.text = (ip.row == 0) ? @"Lancer le diagnostic (diag)" : @"État détaillé (status)";
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (ip.row == 0) { cell.textLabel.text = @"Version"; cell.detailTextLabel.text =
            [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"—"; }
        else if (ip.row == 1) { cell.textLabel.text = @"Paquet"; cell.detailTextLabel.text = @"party.jailbreak.omega"; }
        else { cell.textLabel.text = @"Rappel"; cell.detailTextLabel.text = @"DNS requis en ligne"; }
    }
    return cell;
}

- (void)toggleAuto:(UISwitch *)sw { [OABridge setBool:sw.on forKey:@"auto_apply"]; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 1) return;
    NSString *cmd = (ip.row == 0) ? @"diag" : @"status";
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"…" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:wait animated:YES completion:nil];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [OABridge runCommand:cmd timeout:20];
        dispatch_async(dispatch_get_main_queue(), ^{
            [wait dismissViewControllerAnimated:YES completion:^{
                UIAlertController *res = [UIAlertController alertControllerWithTitle:cmd message:out preferredStyle:UIAlertControllerStyleAlert];
                [res addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [ws presentViewController:res animated:YES completion:nil];
            }];
        });
    });
}

@end
