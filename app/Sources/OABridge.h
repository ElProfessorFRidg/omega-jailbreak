#import <Foundation/Foundation.h>

// Talks to the root trigger daemon and owns the shared config file.
// All command calls BLOCK waiting for the daemon's reply, so call them off
// the main thread (see -runCommand:).
@interface OABridge : NSObject

extern NSString *const kOmegaDir;      // /var/mobile/.omega
extern NSString *const kOmegaLog;      // worker log
extern NSString *const kOmegaProfile;  // generated local-DNS .mobileconfig

// Ask the root daemon to run a command line (e.g. @"apply", @"dns-install 9.9.9.9")
// and return its combined output, or an explanatory error string.
+ (NSString *)runCommand:(NSString *)cmd timeout:(NSTimeInterval)seconds;

+ (NSString *)readLog;

// --- shared config (/var/mobile/.omega/config, KEY=VALUE per line) ---------
+ (NSDictionary<NSString *, NSString *> *)config;
+ (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key fallback:(NSString *)fallback;
+ (void)setString:(NSString *)value forKey:(NSString *)key;

@end
