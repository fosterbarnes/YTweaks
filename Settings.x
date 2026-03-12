#import <PSHeader/Misc.h>
#import <YouTubeHeader/YTSettingsGroupData.h>
#import <YouTubeHeader/YTSettingsSectionItem.h>
#import <YouTubeHeader/YTSettingsSectionItemManager.h>
#import <YouTubeHeader/YTSettingsViewController.h>
#import <YouTubeHeader/YTToastResponderEvent.h>
#import <YouTubeHeader/YTSettingsCell.h>
#import <YouTubeHeader/YTAlertView.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#define Prefix @"YTWKS"

#define _LOC(b, x) [b localizedStringForKey:x value:nil table:nil]
#define LOC(x) _LOC(tweakBundle, x)

static const NSInteger YTWKSSection = 'ytwk'; // For YouGroupSettings

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

    // Fullscreen Mode with segmented control (Off | Left | Right)
    // Level 0 = Off, 1 = Left, 2 = Right
    YTSettingsSectionItem *fullscreenMode = [YTSettingsSectionItemClass itemWithTitle:LOC(@"FULLSCREEN_MODE")
        titleDescription:nil
        accessibilityIdentifier:@"fullscreenModeSegment"
        detailTextBlock:nil
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            return NO; // Non-interactive - segmented control handles selection
        }];
    [sectionItems addObject:fullscreenMode];

    // Night Mode with segmented control (Off | Low | Medium | High | Maximum)
    // Level 0 = Off, 1 = Low (0.3), 2 = Medium (0.5), 3 = High (0.7), 4 = Maximum (0.9)
    YTSettingsSectionItem *nightMode = [YTSettingsSectionItemClass itemWithTitle:LOC(@"NIGHT_MODE")
        titleDescription:nil
        accessibilityIdentifier:@"nightModeSegment"
        detailTextBlock:nil
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            return NO; // Non-interactive - segmented control handles selection
        }];
    [sectionItems addObject:nightMode];

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

    // Fix Casting
    YTSettingsSectionItem *fixCasting = [YTSettingsSectionItemClass switchItemWithTitle:LOC(@"FIX_CASTING")
        titleDescription:LOC(@"FIX_CASTING_DESC")
        accessibilityIdentifier:nil
        switchOn:[defaults boolForKey:@"fixCasting_enabled"]
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [defaults setBool:enabled forKey:@"fixCasting_enabled"];
            [defaults synchronize];
            return YES;
        }
        settingItemId:5];
    [sectionItems addObject:fixCasting];

    // Hide AI Summaries (Experimental)
    YTSettingsSectionItem *hideAISummaries = [YTSettingsSectionItemClass switchItemWithTitle:LOC(@"HIDE_AI_SUMMARIES")
        titleDescription:LOC(@"HIDE_AI_SUMMARIES_DESC")
        accessibilityIdentifier:nil
        switchOn:[defaults boolForKey:@"hideAISummaries_enabled"]
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [defaults setBool:enabled forKey:@"hideAISummaries_enabled"];
            [defaults synchronize];
            return YES;
        }
        settingItemId:4];
    [sectionItems addObject:hideAISummaries];

    // Version number footer (at the bottom)
    #define TWEAK_VERSION 0.4.1
    #define STRINGIFY(x) #x
    #define TOSTRING(x) STRINGIFY(x)
    NSString *versionString = [NSString stringWithFormat:@"YTweaks v%s", TOSTRING(TWEAK_VERSION)];
    YTSettingsSectionItem *versionFooter = [YTSettingsSectionItemClass itemWithTitle:versionString
        titleDescription:nil
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            return NO; // Non-interactive footer
        }];
    [sectionItems addObject:versionFooter];

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
        if ([key hasPrefix:@"fullscreen_mode"] || 
            [key hasPrefix:@"enable"] ||
            [key hasPrefix:@"virtualBezel"] ||
            [key hasPrefix:@"hideAISummaries"] ||
            [key hasPrefix:@"fixCasting"] ||
            [key hasPrefix:@"nightMode"]) {
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
        
        // Update night mode overlay after importing
        [[NSNotificationCenter defaultCenter] postNotificationName:@"YTWKSNightModeChanged" object:nil];
        
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
    NSArray *keys = @[@"fullscreen_mode", 
                      @"enableIosFloatingMiniplayer",
                      @"virtualBezel_enabled",
                      @"hideAISummaries_enabled",
                      @"fixCasting_enabled",
                      @"nightMode_level"];
    
    for (NSString *key in keys) {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
    
    // Update night mode overlay after restoring defaults
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YTWKSNightModeChanged" object:nil];
}

%end

%hook YTSettingsCell

- (void)layoutSubviews {
    %orig;
    
    NSBundle *bundle = YTWKSBundle();
    
    // Night Mode segmented control
    if ([self.accessibilityIdentifier isEqualToString:@"nightModeSegment"]) {
        UISegmentedControl *segment = [self.contentView viewWithTag:888888];
        if (!segment) {
            NSArray *items = @[
                [bundle localizedStringForKey:@"NIGHT_MODE_OFF" value:@"Off" table:nil],
                [bundle localizedStringForKey:@"NIGHT_MODE_LOW" value:@"Low" table:nil],
                [bundle localizedStringForKey:@"NIGHT_MODE_MEDIUM" value:@"Medium" table:nil],
                [bundle localizedStringForKey:@"NIGHT_MODE_HIGH" value:@"High" table:nil],
                [bundle localizedStringForKey:@"NIGHT_MODE_MAXIMUM" value:@"Maximum" table:nil]
            ];
            segment = [[UISegmentedControl alloc] initWithItems:items];
            segment.tag = 888888;
            segment.selectedSegmentIndex = [defaults integerForKey:@"nightMode_level"];
            [segment addTarget:self action:@selector(nightModeSegmentChanged:) forControlEvents:UIControlEventValueChanged];
            
            // Style for dark mode
            segment.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];
            if (@available(iOS 13.0, *)) {
                segment.selectedSegmentTintColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0];
            }
            [segment setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
            [segment setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
            
            // Use smaller font to fit all options
            UIFont *smallFont = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
            [segment setTitleTextAttributes:@{NSFontAttributeName: smallFont, NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
            [segment setTitleTextAttributes:@{NSFontAttributeName: smallFont, NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
            
            segment.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:segment];
            
            // Position below the title with constraints
            [NSLayoutConstraint activateConstraints:@[
                [segment.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
                [segment.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
                [segment.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
                [segment.heightAnchor constraintEqualToConstant:32]
            ]];
        } else {
            // Update selection if it changed externally
            NSInteger currentLevel = [defaults integerForKey:@"nightMode_level"];
            if (segment.selectedSegmentIndex != currentLevel) {
                segment.selectedSegmentIndex = currentLevel;
            }
        }
        return;
    }
    
    // Fullscreen Mode segmented control (Off | Left | Right)
    if ([self.accessibilityIdentifier isEqualToString:@"fullscreenModeSegment"]) {
        UISegmentedControl *segment = [self.contentView viewWithTag:888889];
        if (!segment) {
            NSArray *items = @[
                [bundle localizedStringForKey:@"FULLSCREEN_OFF" value:@"Off" table:nil],
                [bundle localizedStringForKey:@"FULLSCREEN_LEFT" value:@"Left" table:nil],
                [bundle localizedStringForKey:@"FULLSCREEN_RIGHT" value:@"Right" table:nil]
            ];
            segment = [[UISegmentedControl alloc] initWithItems:items];
            segment.tag = 888889;
            segment.selectedSegmentIndex = [defaults integerForKey:@"fullscreen_mode"];
            [segment addTarget:self action:@selector(fullscreenModeSegmentChanged:) forControlEvents:UIControlEventValueChanged];
            
            // Style for dark mode
            segment.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];
            if (@available(iOS 13.0, *)) {
                segment.selectedSegmentTintColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0];
            }
            [segment setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
            [segment setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
            
            // Standard font size (fewer options than night mode)
            UIFont *font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
            [segment setTitleTextAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
            [segment setTitleTextAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
            
            segment.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:segment];
            
            // Position below the title with constraints
            [NSLayoutConstraint activateConstraints:@[
                [segment.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
                [segment.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
                [segment.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
                [segment.heightAnchor constraintEqualToConstant:32]
            ]];
        } else {
            // Update selection if it changed externally
            NSInteger currentMode = [defaults integerForKey:@"fullscreen_mode"];
            if (segment.selectedSegmentIndex != currentMode) {
                segment.selectedSegmentIndex = currentMode;
            }
        }
        return;
    }
    
    // Make the preferences management header smaller and non-clickable
    NSString *headerText = [bundle localizedStringForKey:@"PREFERENCES_MANAGEMENT" value:nil table:nil];
    
    BOOL isHeaderCell = NO;
    UILabel *titleLabel = nil;
    
    @try {
        titleLabel = [self valueForKey:@"_titleLabel"];
        if (!titleLabel) {
            titleLabel = [self valueForKey:@"titleLabel"];
        }
        
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
            self.userInteractionEnabled = NO;
            titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        }
        
        // Style version footer (smaller, lighter)
        NSString *versionPrefix = @"YTweaks ";
        if (titleLabel && [titleLabel.text hasPrefix:versionPrefix]) {
            self.userInteractionEnabled = NO;
            titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightLight];
        }
    } @catch (NSException *e) {
        // Couldn't access properties
    }
}

%new
- (void)nightModeSegmentChanged:(UISegmentedControl *)sender {
    [defaults setInteger:sender.selectedSegmentIndex forKey:@"nightMode_level"];
    [defaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YTWKSNightModeChanged" object:nil];
}

%new
- (void)fullscreenModeSegmentChanged:(UISegmentedControl *)sender {
    [defaults setInteger:sender.selectedSegmentIndex forKey:@"fullscreen_mode"];
    [defaults synchronize];
}

%end

%ctor {
    defaults = [NSUserDefaults standardUserDefaults];
    %init;
}
