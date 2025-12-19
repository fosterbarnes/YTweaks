#import <PSHeader/Misc.h>
#import <YouTubeHeader/YTSettingsGroupData.h>
#import <YouTubeHeader/YTSettingsSectionItem.h>
#import <YouTubeHeader/YTSettingsSectionItemManager.h>
#import <YouTubeHeader/YTSettingsViewController.h>
#import <YouTubeHeader/YTSettingsCell.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#define Prefix @"YTWKS"

#define _LOC(b, x) [b localizedStringForKey:x value:nil table:nil]
#define LOC(x) _LOC(tweakBundle, x)

static const NSInteger YTWKSSection = 'ytwk';  // Use integer between YTUHD and YouPiP

@interface YTAlertView : UIView
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
+ (instancetype)confirmationDialogWithAction:(void (^)(void))action 
                                 actionTitle:(NSString *)actionTitle
                                cancelAction:(void (^)(void))cancelAction
                                 cancelTitle:(NSString *)cancelTitle;
- (void)show;
@end

@interface YTToastResponderEvent : NSObject
+ (instancetype)eventWithMessage:(NSString *)message firstResponder:(UIResponder *)responder;
- (void)send;
@end

@interface YTSettingsSectionItemManager (YTweaks) <UIDocumentPickerDelegate>
@property (nonatomic, assign) BOOL isImportingPreferences;
- (void)updateYTWKSSectionWithEntry:(id)entry;
- (void)exportPreferences;
- (void)importPreferences;
- (void)restoreDefaults;
@end

NSUserDefaults *defaults;

NSBundle *YTWKSBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YTWKS" ofType:@"bundle"];
        bundle = [NSBundle bundleWithPath:tweakBundlePath ?: PS_ROOT_PATH_NS(@"/Library/Application Support/" Prefix ".bundle")];
    });
    return bundle;
}

%hook YTSettingsGroupData

- (NSArray <NSNumber *> *)orderedCategories {
    if (self.type != 1 || class_getClassMethod(objc_getClass("YTSettingsGroupData"), @selector(tweaks)))
        return %orig;
    NSMutableArray *mutableCategories = %orig.mutableCopy;
    // Check if YTWKSSection already exists to avoid duplicates
    NSNumber *sectionNumber = @(YTWKSSection);
    if (![mutableCategories containsObject:sectionNumber]) {
        [mutableCategories insertObject:sectionNumber atIndex:0];
    }
    return mutableCategories.copy;
}

%end

%hook YTAppSettingsPresentationData

+ (NSArray <NSNumber *> *)settingsCategoryOrder {
    NSArray <NSNumber *> *order = %orig;
    NSUInteger insertIndex = [order indexOfObject:@(1)];  // Find "Tweaks" section (1)
    if (insertIndex != NSNotFound) {
        NSMutableArray <NSNumber *> *mutableOrder = [order mutableCopy];
        // Check if YTWKSSection already exists to avoid duplicates
        NSNumber *sectionNumber = @(YTWKSSection);
        if (![mutableOrder containsObject:sectionNumber]) {
            [mutableOrder insertObject:sectionNumber atIndex:insertIndex + 1];
        }
        order = mutableOrder.copy;
    }
    return order;
}

%end

%hook YTSettingsSectionItemManager

%new
- (void)setIsImportingPreferences:(BOOL)isImportingPreferences {
    objc_setAssociatedObject(self, @selector(isImportingPreferences), @(isImportingPreferences), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (BOOL)isImportingPreferences {
    return [objc_getAssociatedObject(self, @selector(isImportingPreferences)) boolValue];
}

%new(v@:@)
- (void)updateYTWKSSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    NSBundle *tweakBundle = YTWKSBundle();
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    // Preferences management header (at the top)
    YTSettingsSectionItem *prefsHeader = [YTSettingsSectionItemClass itemWithTitle:LOC(@"PREFERENCES_MANAGEMENT")
        titleDescription:nil
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            return NO; // Non-interactive header
        }];
    [sectionItems addObject:prefsHeader];

    // Import preferences
    YTSettingsSectionItem *importPrefs = [YTSettingsSectionItemClass itemWithTitle:LOC(@"IMPORT_PREFERENCES")
        titleDescription:nil
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
                [self importPreferences];
            }
            actionTitle:LOC(@"YES")
            cancelAction:^{}
            cancelTitle:LOC(@"CANCEL")];
            alertView.title = LOC(@"WARNING");
            alertView.subtitle = LOC(@"IMPORT_CONFIRM");
            [alertView show];
            return YES;
        }];
    [sectionItems addObject:importPrefs];

    // Export preferences
    YTSettingsSectionItem *exportPrefs = [YTSettingsSectionItemClass itemWithTitle:LOC(@"EXPORT_PREFERENCES")
        titleDescription:nil
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            [self exportPreferences];
            return YES;
        }];
    [sectionItems addObject:exportPrefs];

    // Restore defaults
    YTSettingsSectionItem *restoreDefaults = [YTSettingsSectionItemClass itemWithTitle:LOC(@"RESTORE_DEFAULTS")
        titleDescription:nil
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
                [self restoreDefaults];
            }
            actionTitle:LOC(@"YES")
            cancelAction:^{}
            cancelTitle:LOC(@"CANCEL")];
            alertView.title = LOC(@"WARNING");
            alertView.subtitle = LOC(@"RESTORE_CONFIRM");
            [alertView show];
            return YES;
        }];
    [sectionItems addObject:restoreDefaults];

    // Fullscreen to the Right
    YTSettingsSectionItem *fullscreenToRight = [YTSettingsSectionItemClass switchItemWithTitle:LOC(@"FULLSCREEN_TO_THE_RIGHT")
        titleDescription:LOC(@"FULLSCREEN_TO_THE_RIGHT_DESC")
        accessibilityIdentifier:nil
        switchOn:[defaults boolForKey:@"fullscreenToTheRight_enabled"]
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [defaults setBool:enabled forKey:@"fullscreenToTheRight_enabled"];
            [defaults synchronize];
            return YES;
        }
        settingItemId:0];
    [sectionItems addObject:fullscreenToRight];

    // Fullscreen to the Left
    YTSettingsSectionItem *fullscreenToLeft = [YTSettingsSectionItemClass switchItemWithTitle:LOC(@"FULLSCREEN_TO_THE_LEFT")
        titleDescription:LOC(@"FULLSCREEN_TO_THE_LEFT_DESC")
        accessibilityIdentifier:nil
        switchOn:[defaults boolForKey:@"fullscreenToTheLeft_enabled"]
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [defaults setBool:enabled forKey:@"fullscreenToTheLeft_enabled"];
            [defaults synchronize];
            return YES;
        }
        settingItemId:1];
    [sectionItems addObject:fullscreenToLeft];

    // A/B settings: Disable Floating Miniplayer
    // YouTube's A/B flag: enableIosFloatingMiniplayer (YES = enabled, NO = disabled)
    // Our switch: ON = disable miniplayer, OFF = enable miniplayer
    BOOL isMiniplayerEnabled = [defaults objectForKey:@"enableIosFloatingMiniplayer"] 
        ? [defaults boolForKey:@"enableIosFloatingMiniplayer"] 
        : YES; // Default: miniplayer enabled (switch OFF)
    YTSettingsSectionItem *disableFloatingMiniplayer = [YTSettingsSectionItemClass switchItemWithTitle:LOC(@"ENABLE_IOS_FLOATING_MINIPLAYER")
        titleDescription:LOC(@"ENABLE_IOS_FLOATING_MINIPLAYER_DESC")
        accessibilityIdentifier:nil
        switchOn:!isMiniplayerEnabled
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL disableMiniplayer) {
            // Invert: switch ON (disable) → save NO (disabled), switch OFF (enable) → save YES (enabled)
            [defaults setBool:!disableMiniplayer forKey:@"enableIosFloatingMiniplayer"];
            [defaults synchronize];
            return YES;
        }
        settingItemId:2];
    [sectionItems addObject:disableFloatingMiniplayer];

    // Virtual bezel in landscape
    YTSettingsSectionItem *virtualBezel = [YTSettingsSectionItemClass switchItemWithTitle:LOC(@"VIRTUAL_BEZEL")
        titleDescription:LOC(@"VIRTUAL_BEZEL_DESC")
        accessibilityIdentifier:nil
        switchOn:[defaults boolForKey:@"virtualBezel_enabled"]
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [defaults setBool:enabled forKey:@"virtualBezel_enabled"];
            [defaults synchronize];
            return YES;
        }
        settingItemId:3];
    [sectionItems addObject:virtualBezel];

    YTSettingsViewController *delegate = [self valueForKey:@"_dataDelegate"];
    NSString *title = @"YTweaks";
    if ([delegate respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)]) {
        YTIIcon *icon = [%c(YTIIcon) new];
        icon.iconType = YT_MAGIC_WAND;
        [delegate setSectionItems:sectionItems
            forCategory:YTWKSSection
            title:title
            icon:icon
            titleDescription:nil
            headerHidden:NO];
    } else
        [delegate setSectionItems:sectionItems
            forCategory:YTWKSSection
            title:title
            titleDescription:nil
            headerHidden:NO];
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == YTWKSSection) {
        [self updateYTWKSSectionWithEntry:entry];
        return;
    }
    %orig;
}

%new
- (void)exportPreferences {
    self.isImportingPreferences = NO;
    
    // Get all preferences
    NSDictionary *prefs = [defaults dictionaryRepresentation];
    
    // Filter only YTweaks keys
    NSMutableDictionary *ytweaksPrefs = [NSMutableDictionary dictionary];
    for (NSString *key in prefs) {
        if ([key hasPrefix:@"fullscreenToTheRight"] || 
            [key hasPrefix:@"fullscreenToTheLeft"] || 
            [key hasPrefix:@"enable"] ||
            [key hasPrefix:@"virtualBezel"]) {
            ytweaksPrefs[key] = prefs[key];
        }
    }
    
    // Write to temp file
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"YTweaks-preferences.plist"];
    [ytweaksPrefs writeToFile:tempPath atomically:YES];
    
    // Present document picker for save
    NSURL *fileURL = [NSURL fileURLWithPath:tempPath];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] 
        initWithURL:fileURL 
        inMode:UIDocumentPickerModeExportToService];
    picker.delegate = self;
    
    YTSettingsViewController *settingsVC = [self valueForKey:@"_dataDelegate"];
    [settingsVC presentViewController:picker animated:YES completion:nil];
}

%new
- (void)importPreferences {
    self.isImportingPreferences = YES;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] 
        initWithDocumentTypes:@[@"public.xml", @"com.apple.property-list"] 
        inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    
    YTSettingsViewController *settingsVC = [self valueForKey:@"_dataDelegate"];
    [settingsVC presentViewController:picker animated:YES completion:nil];
}

%new
- (void)documentPicker:(UIDocumentPickerViewController *)controller 
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    
    // Only process for import operations, ignore export
    if (!self.isImportingPreferences) return;
    
    if (urls.count == 0) return;
    
    NSURL *fileURL = urls[0];
    NSDictionary *importedPrefs = [NSDictionary dictionaryWithContentsOfURL:fileURL];
    
    NSBundle *bundle = YTWKSBundle();
    if (importedPrefs) {
        // Import preferences
        for (NSString *key in importedPrefs) {
            [defaults setObject:importedPrefs[key] forKey:key];
        }
        [defaults synchronize];
        
        // Show success message
        NSString *successMsg = [bundle localizedStringForKey:@"IMPORT_SUCCESS" value:nil table:nil];
        [[%c(YTToastResponderEvent) eventWithMessage:successMsg 
            firstResponder:[self parentResponder]] send];
    } else {
        NSString *failMsg = [bundle localizedStringForKey:@"IMPORT_FAILED" value:nil table:nil];
        [[%c(YTToastResponderEvent) eventWithMessage:failMsg 
            firstResponder:[self parentResponder]] send];
    }
}

%new
- (void)restoreDefaults {
    NSArray *keys = @[@"fullscreenToTheRight_enabled", 
                      @"fullscreenToTheLeft_enabled", 
                      @"enableIosFloatingMiniplayer",
                      @"virtualBezel_enabled"];
    
    for (NSString *key in keys) {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

%end

%hook YTSettingsCell

- (void)layoutSubviews {
    %orig;
    
    // Make the preferences management header smaller and non-clickable
    // Identify the header by searching for the localized text
    NSBundle *bundle = YTWKSBundle();
    NSString *headerText = [bundle localizedStringForKey:@"PREFERENCES_MANAGEMENT" value:nil table:nil];
    
    // Search for the header text in the cell's labels
    BOOL isHeaderCell = NO;
    UILabel *titleLabel = nil;
    
    @try {
        // Try to get title label directly
        titleLabel = [self valueForKey:@"_titleLabel"];
        if (!titleLabel) {
            titleLabel = [self valueForKey:@"titleLabel"];
        }
        
        // If not found, search subviews
        if (!titleLabel) {
            for (UIView *subview in self.contentView.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel *)subview;
                    if ([label.text isEqualToString:headerText]) {
                        titleLabel = label;
                        isHeaderCell = YES;
                        break;
                    }
                }
            }
        } else if (titleLabel && [titleLabel.text isEqualToString:headerText]) {
            isHeaderCell = YES;
        }
        
        if (isHeaderCell && titleLabel) {
            // Disable user interaction
            self.userInteractionEnabled = NO;
            
            // Make text smaller
            titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        }
    } @catch (NSException *e) {
        // Couldn't access properties
    }
}

%end

%ctor {
    defaults = [NSUserDefaults standardUserDefaults];
    %init;
}
