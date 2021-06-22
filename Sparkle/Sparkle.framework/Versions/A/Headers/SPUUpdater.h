//
//  SPUUpdater.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
#import <Sparkle/SUExport.h>
#import <Sparkle/SPUUserDriver.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem, SUAppcast;

@protocol SPUUpdaterDelegate;

/*!
    The main API in Sparkle for controlling the update mechanism.

    This class is used to configure the update parameters as well as manually
    and automatically schedule and control checks for updates.
 */
SU_EXPORT @interface SPUUpdater : NSObject

/*!
 Initializes a new SPUUpdater instance
 
 This does not start the updater. To start it, see -[SPUUpdater startUpdater:]
 
 Note that this is a normal initializer and doesn't implement the singleton pattern (i.e, instances aren't cached, so no surprises)
 This also means that updater instances can be deallocated, and that they will be torn down properly.
 
 Related: See SPUStandardUpdaterController which wraps a SPUUpdater instance and is suitable for instantiating in nib files
 
 @param hostBundle The bundle that should be targetted for updating. This must not be nil.
 @param applicationBundle The application bundle that should be waited for termination and relaunched (unless overridden). Usually this can be the same as hostBundle. This may differ when updating a plug-in or other non-application bundle.
 @param userDriver The user driver that Sparkle uses for user update interaction
 @param delegate The delegate for SPUUpdater. This may be nil.
 */
- (instancetype)initWithHostBundle:(NSBundle *)hostBundle applicationBundle:(NSBundle *)applicationBundle userDriver:(id <SPUUserDriver>)userDriver delegate:(id<SPUUpdaterDelegate> _Nullable)delegate;

/*!
 Use -initWithHostBundle:applicationBundle:userDriver:delegate: or SPUStandardUpdaterController standard adapter instead.
 
 If you want to drop an updater into a nib, use SPUStandardUpdaterController.
 */
- (instancetype)init NS_UNAVAILABLE;

/*!
 Starts the updater.

 This method checks if Sparkle is configured properly. A valid feed URL should be set before this method is invoked.
 Other properties of this SPUUpdater instance can be set before this method is invoked as well, such as automatic update checks.

 If the configuration is valid, an update cycle is started in the next main runloop cycle.
 During this cycle, a permission prompt may be brought up (if needed) for checking if the user wants automatic update checking.
 Otherwise if automatic update checks are enabled, a scheduled update alert may be brought up if enough time has elapsed since the last check.

 After starting the updater and before the next runloop cycle, one of -checkForUpdates, -checkForUpdatesInBackground, or -checkForUpdateInformation can be invoked.
 This may be useful if you want to check for updates immediately or without showing a permission prompt.

 This must be called on the main thread.

 @param error The error that is populated if this method fails. Pass NULL if not interested in the error information.
 @return YES if the updater started otherwise NO with a populated error
 */
- (BOOL)startUpdater:(NSError * __autoreleasing *)error;

/*!
 Checks for updates, and displays progress while doing so if needed.
 
 This is meant for users initiating a new update check or checking the current update progress.
 
 If an update hasn't started, the user may be shown that a new check for updates is occurring.
 If an update has already been downloaded or begun installing, the user may be presented to install that update.
 If the user is already being presented with an update, that update will be shown to the user in active focus.
 
 This will find updates that the user has previously opted into skipping.
 
 See canCheckForUpdates property which can determine if this method may be invoked.
 */
- (void)checkForUpdates;

/*!
 Checks for updates, but does not display any UI unless an update is found.
 
 This is meant for programmatically initating a check for updates.
 That is, it will display no UI unless it finds an update, in which case it proceeds as usual.
 This will not find updates that the user has opted into skipping.
 
 Note if there is no resumable update found, and automated updating is turned on,
 the update will be downloaded in the background without disrupting the user.
 */
- (void)checkForUpdatesInBackground;

/*!
 Begins a "probing" check for updates which will not actually offer to
 update to that version.
 
 However, the delegate methods
 SPUUpdaterDelegate::updater:didFindValidUpdate: and
 SPUUpdaterDelegate::updaterDidNotFindUpdate: will be called,
 so you can use that information in your UI.
 
 Updates that have been skipped by the user will not be found.
 */
- (void)checkForUpdateInformation;

/*!
 A property indicating whether or not updates can be checked by the user.
 
 An update check can be made by the user when an update session isn't in progress, or when an update or its progress is being shown to the user.
 
 This property is suitable to use for menu item validation for seeing if -checkForUpdates can be invoked.
 
 Note this property does not reflect whether or not an update session is in progress. Please see sessionInProgress property instead.
 */
@property (nonatomic, readonly) BOOL canCheckForUpdates;

/*!
 A property indicating whether or not an update session is in progress.
 
 An update session is in progress when the appcast is being downloaded, an update is being downloaded,
 an update is being shown, update permission is being requested, or the installer is being started.
 An active session is when Sparkle's fired scheduler is running.
 
 Note an update session may be inactive even though Sparkle's installer (ran as a separate process) may be running,
 or even though the update has been downloaded but the installation has been deferred. In both of these cases, a new update session
 may be activated with the update resumed at a later point (automatically or manually).
 
 See also canCheckForUpdates property which is more suited for menu item validation.
 */
@property (nonatomic, readonly) BOOL sessionInProgress;

/*!
 A property indicating whether or not to check for updates automatically.
 
 Setting this property will persist in the host bundle's user defaults.
 The update schedule cycle will be reset in a short delay after the property's new value is set.
 This is to allow reverting this property without kicking off a schedule change immediately
 */
@property (nonatomic) BOOL automaticallyChecksForUpdates;

/*!
 A property indicating the current automatic update check interval.
 
 Setting this property will persist in the host bundle's user defaults.
 The update schedule cycle will be reset in a short delay after the property's new value is set.
 This is to allow reverting this property without kicking off a schedule change immediately
 */
@property (nonatomic) NSTimeInterval updateCheckInterval;

/*!
 A property indicating whether or not updates can be automatically downloaded in the background.
 
 Note that the developer can disallow automatic downloading of updates from being enabled.
 In this case, -automaticallyDownloadsUpdates will return NO regardless of how this property is set.
 
 Setting this property will persist in the host bundle's user defaults.
 */
@property (nonatomic) BOOL automaticallyDownloadsUpdates;

/*!
 The URL of the appcast used to download update information.
 
 If the updater's delegate implements -[SPUUpdaterDelegate feedURLStringForUpdater:], this will return that feed URL.
 Otherwise if the feed URL has been set before, the feed URL returned will be retrieved from the host bundle's user defaults.
 Otherwise the feed URL in the host bundle's Info.plist will be returned.
 If no feed URL can be retrieved, returns nil.
 
 This property must be called on the main thread; calls from background threads will return nil.
 */
@property (nonatomic, readonly, nullable) NSURL *feedURL;

/*!
 Set the URL of the appcast used to download update information. Using this method is discouraged.
 
 Setting this property will persist in the host bundle's user defaults.
 To avoid this, you should consider instead implementing
 -[SPUUpdaterDelegate feedURLStringForUpdater:] or -[SPUUpdaterDelegate feedParametersForUpdater:sendingSystemProfile:]
 
 Passing nil will remove any feed URL that has been set in the host bundle's user defaults.
 
 This method must be called on the main thread; calls from background threads will have no effect.
 */
- (void)setFeedURL:(NSURL * _Nullable)feedURL;

/*!
 The host bundle that is being updated.
 */
@property (nonatomic, readonly) NSBundle *hostBundle;

/*!
 The bundle this class (SPUUpdater) is loaded into
 */
@property (nonatomic, readonly) NSBundle *sparkleBundle;

/*!
 * The user agent used when checking for updates.
 *
 * The default implementation can be overrided.
 */
@property (nonatomic, copy) NSString *userAgentString;

/*!
 The HTTP headers used when checking for updates.
 
 The keys of this dictionary are HTTP header fields (NSString) and values are corresponding values (NSString)
 */
#if __has_feature(objc_generics)
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *httpHeaders;
#else
@property (nonatomic, copy, nullable) NSDictionary *httpHeaders;
#endif

/*!
 A property indicating whether or not the user's system profile information is sent when checking for updates.

 Setting this property will persist in the host bundle's user defaults.
 */
@property (nonatomic) BOOL sendsSystemProfile;

/*!
    Returns the date of last update check.

    \returns \c nil if no check has been performed.
 */
@property (nonatomic, readonly, copy, nullable) NSDate *lastUpdateCheckDate;

/*!
    Appropriately schedules or cancels the update checking timer according to
    the preferences for time interval and automatic checks.

    This call does not change the date of the next check,
    but only the internal timer.
 */
- (void)resetUpdateCycle;


/*!
 The system profile information that is sent when checking for updates
 */
@property (nonatomic, readonly, copy) NSArray<NSDictionary<NSString *, NSString *> *> *systemProfileArray;

@end

NS_ASSUME_NONNULL_END
