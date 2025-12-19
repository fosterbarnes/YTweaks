#import <substrate.h>
#import <UIKit/UIKit.h>
#import <YouTubeHeader/YTAppDelegate.h>
#import <YouTubeHeader/YTGlobalConfig.h>
#import <YouTubeHeader/YTColdConfig.h>
#import <YouTubeHeader/YTHotConfig.h>

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
    
    // Calculate 16:9 aspect ratio region centered on screen
    CGFloat aspectRatio = 16.0 / 9.0;
    CGFloat videoWidth, videoHeight;
    
    if (screenWidth / screenHeight > aspectRatio) {
        // Screen is wider than 16:9, so video height matches screen height
        videoHeight = screenHeight;
        videoWidth = videoHeight * aspectRatio;
    } else {
        // Screen is taller than 16:9, so video width matches screen width
        videoWidth = screenWidth;
        videoHeight = videoWidth / aspectRatio;
    }
    
    // Center the video region
    CGFloat videoX = (screenWidth - videoWidth) / 2.0;
    
    // Only create blocking views if there's space on the sides
    if (videoX > 0) {
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
        leftBlocker.frame = CGRectMake(0, 0, videoX, screenHeight);
    } else {
        // Remove left blocker if no space
        UIView *leftBlocker = [view viewWithTag:999998];
        if (leftBlocker) [leftBlocker removeFromSuperview];
    }
    
    CGFloat rightBlockerX = videoX + videoWidth;
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
