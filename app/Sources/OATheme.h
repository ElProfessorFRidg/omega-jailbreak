#import <UIKit/UIKit.h>

// Central place for the app's look: colours, fonts, and small view factories
// so every screen reads as one design.
@interface OATheme : NSObject

+ (UIColor *)bg;        // window / table background
+ (UIColor *)card;      // raised surfaces
+ (UIColor *)stroke;    // hairline borders
+ (UIColor *)text;      // primary label
+ (UIColor *)subtext;   // secondary label
+ (UIColor *)accent;    // brand red
+ (UIColor *)green;
+ (UIColor *)blue;
+ (UIColor *)purple;
+ (UIColor *)amber;

+ (UIFont *)mono:(CGFloat)size;

// A filled, rounded action button (52pt tall) with a bold title.
+ (UIButton *)button:(NSString *)title color:(UIColor *)color;
// A rounded card container to drop subviews into.
+ (UIView *)card:(UIView *)parent;
// A monospaced, read-only console-style text view.
+ (UITextView *)console;

@end
