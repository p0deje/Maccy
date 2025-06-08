//
//  SPUUpdaterSettings.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/27/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#if defined(BUILDING_SPARKLE_SOURCES_EXTERNALLY)
// Ignore incorrect warning
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wquoted-include-in-framework-header"
#import "SUExport.h"
#pragma clang diagnostic pop
#else
#import <Sparkle/SUExport.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/**
 This class can be used for reading certain updater settings.
 
 It retrieves the settings by first looking into the host's user defaults.
 If the setting is not found in there, then the host's Info.plist file is looked at.
 */
SU_EXPORT @interface SPUUpdaterSettings : NSObject

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle;

/**
 * Indicates whether or not automatic update checks are enabled.
 */
@property (readonly, nonatomic) BOOL automaticallyChecksForUpdates;

/**
 * The regular update check interval.
 */
@property (readonly, nonatomic) NSTimeInterval updateCheckInterval;

/**
 * Indicates whether or not automatically downloading updates is allowed to be turned on by the user.
 * If this value is nil, the developer has not explicitly specified this option.
 */
@property (readonly, nonatomic, nullable) NSNumber *allowsAutomaticUpdatesOption;

/**
 * Indicates whether or not automatically downloading updates is allowed to be turned on by the user.
 */
@property (readonly, nonatomic) BOOL allowsAutomaticUpdates;

/**
 * Indicates whether or not automatically downloading updates is enabled by the user or developer.
 *
 * Note this does not indicate whether or not automatic downloading of updates is allowable.
 * See `-allowsAutomaticUpdates` property for that.
 */
@property (readonly, nonatomic) BOOL automaticallyDownloadsUpdates;

/**
 * Indicates whether or not anonymous system profile information is sent when checking for updates.
 */
@property (readonly, nonatomic) BOOL sendsSystemProfile;

@end

NS_ASSUME_NONNULL_END
