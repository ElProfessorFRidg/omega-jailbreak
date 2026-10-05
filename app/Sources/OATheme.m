#import "OATheme.h"

@implementation OATheme

+ (UIColor *)bg      { return [UIColor colorWithRed:0.043 green:0.051 blue:0.063 alpha:1.0]; }
+ (UIColor *)card    { return [UIColor colorWithRed:0.09  green:0.10  blue:0.12  alpha:1.0]; }
+ (UIColor *)stroke  { return [UIColor colorWithWhite:1.0 alpha:0.08]; }
+ (UIColor *)text    { return [UIColor colorWithWhite:0.96 alpha:1.0]; }
+ (UIColor *)subtext { return [UIColor colorWithWhite:0.62 alpha:1.0]; }
+ (UIColor *)accent  { return [UIColor colorWithRed:0.82 green:0.24 blue:0.19 alpha:1.0]; }
+ (UIColor *)green   { return [UIColor colorWithRed:0.20 green:0.62 blue:0.34 alpha:1.0]; }
+ (UIColor *)blue    { return [UIColor colorWithRed:0.20 green:0.44 blue:0.78 alpha:1.0]; }
+ (UIColor *)purple  { return [UIColor colorWithRed:0.46 green:0.34 blue:0.70 alpha:1.0]; }
+ (UIColor *)amber   { return [UIColor colorWithRed:0.85 green:0.60 blue:0.20 alpha:1.0]; }

+ (UIFont *)mono:(CGFloat)size {
    return [UIFont fontWithName:@"Menlo" size:size] ?: [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
}

+ (UIButton *)button:(NSString *)title color:(UIColor *)color {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    b.backgroundColor = color;
    b.layer.cornerRadius = 13;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.heightAnchor constraintEqualToConstant:52].active = YES;
    return b;
}

+ (UIView *)card:(UIView *)parent {
    UIView *v = [[UIView alloc] init];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = [OATheme card];
    v.layer.cornerRadius = 16;
    v.layer.borderWidth = 1;
    v.layer.borderColor = [OATheme stroke].CGColor;
    if (parent) [parent addSubview:v];
    return v;
}

+ (UITextView *)console {
    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.backgroundColor = [UIColor colorWithRed:0.02 green:0.027 blue:0.039 alpha:1.0];
    tv.textColor = [OATheme text];
    tv.font = [OATheme mono:12];
    tv.layer.cornerRadius = 12;
    tv.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    return tv;
}

@end
