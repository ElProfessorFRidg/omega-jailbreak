#import "OABridge.h"

NSString *const kOmegaDir     = @"/var/mobile/.omega";
NSString *const kOmegaLog     = @"/var/mobile/omega-ondevice.log";
NSString *const kOmegaProfile = @"/var/mobile/.omega/Omega-LocalDNS.mobileconfig";

static NSString *CfgPath(void) { return [kOmegaDir stringByAppendingPathComponent:@"config"]; }

// The keys the app knows about, with their defaults, so a missing config file
// still yields a sensible full config to rewrite.
static NSDictionary *Defaults(void) {
    return @{ @"mod_ocsp": @"1", @"mod_banlists": @"1", @"mod_valid": @"0",
              @"mod_restart": @"1", @"auto_apply": @"0", @"dns_upstream": @"1.1.1.1" };
}

@implementation OABridge

+ (NSString *)runCommand:(NSString *)cmd timeout:(NSTimeInterval)seconds {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:kOmegaDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *cmdF = [kOmegaDir stringByAppendingPathComponent:@"cmd"];
    NSString *outF = [kOmegaDir stringByAppendingPathComponent:@"out"];
    NSString *trgF = [kOmegaDir stringByAppendingPathComponent:@"trigger"];

    NSError *e = nil;
    if (![cmd writeToFile:cmdF atomically:YES encoding:NSUTF8StringEncoding error:&e]) {
        return [NSString stringWithFormat:
            @"Impossible d'écrire %@\n%@\n\nL'app n'a pas accès à /var/mobile ?", cmdF, e.localizedDescription];
    }
    NSDate *prev = [[fm attributesOfItemAtPath:outF error:nil] fileModificationDate];

    NSString *nonce = [NSString stringWithFormat:@"%f", NSDate.date.timeIntervalSince1970];
    if (![nonce writeToFile:trgF atomically:YES encoding:NSUTF8StringEncoding error:&e]) {
        return [NSString stringWithFormat:@"Impossible de déclencher le démon : %@", e.localizedDescription];
    }

    int ticks = (int)(seconds / 0.2);
    for (int i = 0; i < ticks; i++) {
        usleep(200000);
        NSDate *now = [[fm attributesOfItemAtPath:outF error:nil] fileModificationDate];
        if (now && (!prev || [now compare:prev] == NSOrderedDescending)) {
            NSString *s = [NSString stringWithContentsOfFile:outF encoding:NSUTF8StringEncoding error:nil];
            return s.length ? s : @"(réponse vide)";
        }
    }
    return @"Pas de réponse du démon root.\n\nLe paquet 'Omega On-Device' est-il "
           @"installé et le démon party.jailbreak.omega.trigger chargé ?";
}

+ (NSString *)readLog {
    NSString *s = [NSString stringWithContentsOfFile:kOmegaLog encoding:NSUTF8StringEncoding error:nil];
    return s.length ? s : @"(log vide)";
}

#pragma mark - config

+ (NSDictionary<NSString *, NSString *> *)config {
    NSMutableDictionary *cfg = [Defaults() mutableCopy];
    NSString *raw = [NSString stringWithContentsOfFile:CfgPath() encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [raw componentsSeparatedByString:@"\n"]) {
        NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (t.length == 0 || [t hasPrefix:@"#"]) continue;
        NSRange eq = [t rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *k = [t substringToIndex:eq.location];
        NSString *v = [t substringFromIndex:eq.location + 1];
        if (k.length) cfg[k] = v;
    }
    return cfg;
}

+ (void)writeConfig:(NSDictionary *)cfg {
    NSMutableString *out = [NSMutableString string];
    NSArray *order = @[@"mod_ocsp", @"mod_banlists", @"mod_valid", @"mod_restart", @"auto_apply", @"dns_upstream"];
    for (NSString *k in order) {
        NSString *v = cfg[k] ?: Defaults()[k];
        if (v) [out appendFormat:@"%@=%@\n", k, v];
    }
    [out writeToFile:CfgPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback {
    NSString *v = [self config][key];
    if (!v) return fallback;
    return [v isEqualToString:@"1"];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    NSMutableDictionary *cfg = [[self config] mutableCopy];
    cfg[key] = value ? @"1" : @"0";
    [self writeConfig:cfg];
}

+ (NSString *)stringForKey:(NSString *)key fallback:(NSString *)fallback {
    NSString *v = [self config][key];
    return v.length ? v : fallback;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key {
    NSMutableDictionary *cfg = [[self config] mutableCopy];
    cfg[key] = value ?: @"";
    [self writeConfig:cfg];
}

@end
