//
//  SPUStandardUserDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Cocoa;
#else
#import <Cocoa/Cocoa.h>
#endif
#import "SPUUserDriver.h"
#import "SUExport.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SPUStandardUserDriverDelegate;

/*!
 Sparkle's standard built-in user driver for updater interactions
 */
SU_EXPORT @interface SPUStandardUserDriver : NSObject <SPUUserDriver>

/*!
 Initializes a Sparkle's standard user driver for user update interactions
 
 @param hostBundle The target bundle of the host that is being updated.
 @param delegate The delegate to this user driver. Pass nil if you don't want to provide one.
 */
- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(nullable id<SPUStandardUserDriverDelegate>)delegate;

/*!
 * Enable or disable hideOnDeactivate for standard update window.
 */
@property (nonatomic) BOOL hideOnDeactivate;

@end

NS_ASSUME_NONNULL_END
