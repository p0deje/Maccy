//
//  SPUUserUpdateState.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/29/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SPUUserUpdateState_h
#define SPUUserUpdateState_h

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif

#import <Sparkle/SUExport.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPUUserUpdateChoice) {
    SPUUserUpdateChoiceSkip,
    SPUUserUpdateChoiceInstall,
    SPUUserUpdateChoiceDismiss,
};

typedef NS_ENUM(NSInteger, SPUUserUpdateStage) {
    SPUUserUpdateStageNotDownloaded,
    SPUUserUpdateStageDownloaded,
    SPUUserUpdateStageInstalling,
    SPUUserUpdateStageInformational
};

SU_EXPORT @interface SPUUserUpdateState : NSObject

@property (nonatomic, readonly) SPUUserUpdateStage stage;
@property (nonatomic, readonly) BOOL userInitiated;
@property (nonatomic, readonly) BOOL majorUpgrade;

@end

NS_ASSUME_NONNULL_END

#endif /* SPUUserUpdateState_h */
