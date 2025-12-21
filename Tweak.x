#import <substrate.h>
#import <UIKit/UIKit.h>
#import <YouTubeHeader/YTAppDelegate.h>
#import <YouTubeHeader/YTGlobalConfig.h>
#import <YouTubeHeader/YTColdConfig.h>
#import <YouTubeHeader/YTHotConfig.h>
#import <YouTubeHeader/YTIElementRenderer.h>

// Forward declarations
@class YTWatchViewController;
@class YTMainAppVideoPlayerOverlayView;

// Storage for original method implementations
NSMutableDictionary <NSString *, NSMutableDictionary <NSString *, NSNumber *> *> *abConfigCache;

// Helper function to get original value from config instance
static BOOL getValueFromInvocation(id target, SEL selector) {
    IMP imp = [target methodForSelector:selector];
    BOOL (*func)(id, SEL) = (BOOL (*)(id, SEL))imp;
    return func(target, selector);
}

// Replacement function for A/B config boolean methods
static BOOL returnFunction(id const self, SEL _cmd) {
    NSString *method = NSStringFromSelector(_cmd);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Check if user has overridden this setting
    if ([defaults objectForKey:method]) {
        return [defaults boolForKey:method];
    }
    
    // Return cached original value if not overridden
    NSString *classKey = NSStringFromClass([self class]);
    NSNumber *cachedValue = abConfigCache[classKey][method];
    return cachedValue ? [cachedValue boolValue] : NO;
}

// Get all boolean methods from a config class
static NSMutableArray <NSString *> *getBooleanMethods(Class clz) {
    NSMutableArray *allMethods = [NSMutableArray array];
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(clz, &methodCount);
    
    for (unsigned int i = 0; i < methodCount; ++i) {
        Method method = methods[i];
        const char *encoding = method_getTypeEncoding(method);
        
        // Only hook boolean return methods: B16@0:8
        if (strcmp(encoding, "B16@0:8")) continue;
        
        NSString *selector = [NSString stringWithUTF8String:sel_getName(method_getName(method))];
        
        // Exclude Android and other irrelevant methods
        if ([selector hasPrefix:@"android"] || 
            [selector hasPrefix:@"amsterdam"] ||
            [selector hasPrefix:@"kidsClient"] ||
            [selector hasPrefix:@"musicClient"] ||
            [selector hasPrefix:@"musicOfflineClient"] ||
            [selector hasPrefix:@"unplugged"] ||
            [selector rangeOfString:@"Android"].location != NSNotFound) {
            continue;
        }
        
        if (![allMethods containsObject:selector])
            [allMethods addObject:selector];
    }
    
    free(methods);
    return allMethods;
}

// Hook all boolean methods in a config class
static void hookClass(NSObject *instance) {
    if (!instance) return;
    
    Class instanceClass = [instance class];
    NSMutableArray <NSString *> *methods = getBooleanMethods(instanceClass);
    NSString *classKey = NSStringFromClass(instanceClass);
    
    // Initialize cache for this class
    NSMutableDictionary *classCache = abConfigCache[classKey] = [NSMutableDictionary new];
    
    // Hook each boolean method
    for (NSString *method in methods) {
        SEL selector = NSSelectorFromString(method);
        
        // Cache the original value
        BOOL result = getValueFromInvocation(instance, selector);
        classCache[method] = @(result);
        
        // Replace with our function that checks NSUserDefaults
        MSHookMessageEx(instanceClass, selector, (IMP)returnFunction, NULL);
    }
}

// Hook YTAppDelegate to intercept A/B config classes on app launch
%hook YTAppDelegate

- (BOOL)application:(id)arg1 didFinishLaunchingWithOptions:(id)arg2 {
    BOOL result = %orig;
    
    // Hook YouTube's A/B config classes
    YTGlobalConfig *globalConfig = nil;
    YTColdConfig *coldConfig = nil;
    YTHotConfig *hotConfig = nil;
    
    @try {
        // Try to get config instances from app delegate
        globalConfig = [self valueForKey:@"_globalConfig"];
        coldConfig = [self valueForKey:@"_coldConfig"];
        hotConfig = [self valueForKey:@"_hotConfig"];
    } @catch (id ex) {
        // Fallback: try getting from _settings
        @try {
            id settings = [self valueForKey:@"_settings"];
            globalConfig = [settings valueForKey:@"_globalConfig"];
            coldConfig = [settings valueForKey:@"_coldConfig"];
            hotConfig = [settings valueForKey:@"_hotConfig"];
        } @catch (id ex) {}
    }
    
    // Hook each config class
    hookClass(globalConfig);
    hookClass(coldConfig);
    hookClass(hotConfig);
    
    return result;
}

%end

// Fullscreen to the Right (iPhone-Exclusive) - @arichornlover & @bhackel
// WARNING: Please turn off any "Portrait Fullscreen" or "iPad Layout" Options while "Fullscreen to the Right" is enabled.
%hook YTWatchViewController
- (UIInterfaceOrientationMask)allowedFullScreenOrientations {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"fullscreenToTheRight_enabled"]) {
        UIInterfaceOrientationMask orientations = UIInterfaceOrientationMaskLandscapeRight;
        return orientations;
    }
    if ([defaults boolForKey:@"fullscreenToTheLeft_enabled"]) {
        UIInterfaceOrientationMask orientations = UIInterfaceOrientationMaskLandscapeLeft;
        return orientations;
    }
    return %orig;
}
%end

// Virtual bezel in landscape mode to prevent accidental video scrubbing
%hook YTMainAppVideoPlayerOverlayView
- (void)layoutSubviews {
    %orig;
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"virtualBezel_enabled"]) {
        // Remove blocking views if feature is disabled
        UIView *view = (UIView *)self;
        UIView *leftBlocker = [view viewWithTag:999998];
        UIView *rightBlocker = [view viewWithTag:999999];
        if (leftBlocker) [leftBlocker removeFromSuperview];
        if (rightBlocker) [rightBlocker removeFromSuperview];
        return;
    }
    
    // Check if we're in landscape orientation
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    
    if (!isLandscape) {
        // Remove blocking views if they exist when not in landscape
        UIView *view = (UIView *)self;
        UIView *leftBlocker = [view viewWithTag:999998];
        UIView *rightBlocker = [view viewWithTag:999999];
        if (leftBlocker) [leftBlocker removeFromSuperview];
        if (rightBlocker) [rightBlocker removeFromSuperview];
        return;
    }
    
    // Get screen dimensions
    UIView *view = (UIView *)self;
    CGRect screenBounds = view.bounds;
    CGFloat screenWidth = screenBounds.size.width;
    CGFloat screenHeight = screenBounds.size.height;
    
    // Calculate 2177:1179 aspect ratio for clickable area (touchable region)
    // This ratio extends the clickable area just enough to reach the settings button
    CGFloat clickableAspectRatio = 2177.0 / 1179.0;
    CGFloat clickableWidth, clickableHeight;
    
    // Calculate clickable area based on aspect ratio
    // In landscape, we want the clickable area to match the aspect ratio
    if (screenWidth / screenHeight > clickableAspectRatio) {
        // Screen is wider than 2177:1179, so clickable height matches screen height
        clickableHeight = screenHeight;
        clickableWidth = clickableHeight * clickableAspectRatio;
    } else {
        // Screen is taller than 2177:1179, so clickable width matches screen width
        clickableWidth = screenWidth;
        clickableHeight = clickableWidth / clickableAspectRatio;
    }
    
    // Center the clickable region
    CGFloat clickableX = (screenWidth - clickableWidth) / 2.0;
    
    // Only create blocking views if there's space on the sides
    if (clickableX > 0) {
        // Create or update left blocking view
        UIView *leftBlocker = [view viewWithTag:999998];
        if (!leftBlocker) {
            leftBlocker = [[UIView alloc] init];
            leftBlocker.tag = 999998;
            leftBlocker.backgroundColor = [UIColor clearColor];
            leftBlocker.userInteractionEnabled = YES;
            leftBlocker.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleHeight;
            [view addSubview:leftBlocker];
        }
        leftBlocker.frame = CGRectMake(0, 0, clickableX, screenHeight);
    } else {
        // Remove left blocker if no space
        UIView *leftBlocker = [view viewWithTag:999998];
        if (leftBlocker) [leftBlocker removeFromSuperview];
    }
    
    CGFloat rightBlockerX = clickableX + clickableWidth;
    CGFloat rightBlockerWidth = screenWidth - rightBlockerX;
    if (rightBlockerWidth > 0) {
        // Create or update right blocking view
        UIView *rightBlocker = [view viewWithTag:999999];
        if (!rightBlocker) {
            rightBlocker = [[UIView alloc] init];
            rightBlocker.tag = 999999;
            rightBlocker.backgroundColor = [UIColor clearColor];
            rightBlocker.userInteractionEnabled = YES;
            rightBlocker.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight;
            [view addSubview:rightBlocker];
        }
        rightBlocker.frame = CGRectMake(rightBlockerX, 0, rightBlockerWidth, screenHeight);
    } else {
        // Remove right blocker if no space
        UIView *rightBlocker = [view viewWithTag:999999];
        if (rightBlocker) [rightBlocker removeFromSuperview];
    }
}
%end

// Hide AI Summaries - Look for sparkle/star icon (✨) and Summary text
static BOOL containsSparkleOrSummary(UIView *view) {
    // Check if view contains sparkle character or "Summary" text
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.text) {
            // Check for sparkle character (✨) or "Summary" text
            NSString *text = label.text;
            if ([text containsString:@"✨"] || 
                [text containsString:@"✧"] ||
                [text containsString:@"✦"] ||
                [text containsString:@" sparkle"] ||
                [text rangeOfString:@"Summary" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return YES;
            }
        }
    }
    
    // Check UIImageView for sparkle icon
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        // Check image description
        NSString *imageDesc = [imageView.image description];
        if (imageDesc && ([imageDesc containsString:@"sparkle"] || 
                          [imageDesc containsString:@"star"] ||
                          [imageDesc containsString:@"magic"] ||
                          [imageDesc containsString:@"wand"])) {
            return YES;
        }
        // Also check if it's a small icon (sparkle icons are typically small)
        if (imageView.frame.size.width < 30 && imageView.frame.size.height < 30 && imageView.image) {
            // Could be a sparkle icon - check if nearby views have "Summary"
            UIView *parent = imageView.superview;
            if (parent) {
                for (UIView *sibling in parent.subviews) {
                    if ([sibling isKindOfClass:[UILabel class]]) {
                        UILabel *siblingLabel = (UILabel *)sibling;
                        if (siblingLabel.text && [siblingLabel.text rangeOfString:@"Summary" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                            return YES;
                        }
                    }
                }
            }
        }
    }
    
    // Check accessibility label
    if (view.accessibilityLabel) {
        NSString *accLabel = view.accessibilityLabel;
        if ([accLabel containsString:@"✨"] ||
            [accLabel containsString:@"✧"] ||
            [accLabel containsString:@"✦"] ||
            [accLabel rangeOfString:@"Summary" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [accLabel containsString:@"sparkle"]) {
            return YES;
        }
    }
    
    return NO;
}

static void hideSummaryViewsInView(UIView *view) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"hideAISummaries_enabled"]) {
        return;
    }
    
    // Search for views containing sparkle icon or "Summary" text
    for (UIView *subview in view.subviews) {
        if (containsSparkleOrSummary(subview)) {
            // Found sparkle icon or Summary text - hide the parent container
            UIView *container = subview.superview;
            int levelsUp = 0;
            // Go up to find the actual button/card container
            while (container && container != view && levelsUp < 6) {
                // Check if this looks like a button or card container
                if ([container isKindOfClass:[UIButton class]] || 
                    container.backgroundColor || 
                    container.layer.cornerRadius > 0 ||
                    container.frame.size.height > 25) { // Likely the summary card/button
                    container.hidden = YES;
                    // Collapse the view by setting height to 0
                    CGRect frame = container.frame;
                    frame.size.height = 0;
                    container.frame = frame;
                    break;
                }
                container = container.superview;
                levelsUp++;
            }
            // Fallback: hide immediate parent if we didn't find a specific container
            if (levelsUp >= 6 && subview.superview) {
                subview.superview.hidden = YES;
                CGRect frame = subview.superview.frame;
                frame.size.height = 0;
                subview.superview.frame = frame;
            }
        }
        
        // Also check if this view itself should be hidden
        if (containsSparkleOrSummary(subview)) {
            // Check siblings for "Summary" text if we found a sparkle icon
            UIView *parent = subview.superview;
            if (parent) {
                for (UIView *sibling in parent.subviews) {
                    if (sibling != subview && containsSparkleOrSummary(sibling)) {
                        // Found both sparkle and summary in same container - hide it
                        parent.hidden = YES;
                        CGRect frame = parent.frame;
                        frame.size.height = 0;
                        parent.frame = frame;
                        break;
                    }
                }
            }
        }
        
        // Recursively check subviews (limit depth to avoid performance issues)
        if (subview.subviews.count > 0 && subview.subviews.count < 50) {
            hideSummaryViewsInView(subview);
        }
    }
}

// Hook collection view cells to hide summary views after layout
%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    hideSummaryViewsInView(self);
}
%end

%ctor {
    [[NSBundle bundleWithPath:[NSString stringWithFormat:@"%@/Frameworks/Module_Framework.framework", [[NSBundle mainBundle] bundlePath]]] load];
    
    // Initialize A/B config cache
    abConfigCache = [NSMutableDictionary new];
    
    %init;
}

%dtor {
    // Clean up cache on unload
    [abConfigCache removeAllObjects];
}
