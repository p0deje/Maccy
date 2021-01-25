//
//  SUUserDriverCoreComponent.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/4/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
#import "SPUStatusCompletionResults.h"
#import "SUExport.h"

@protocol SPUStandardUserDriverDelegate;

SU_EXPORT @interface SPUUserDriverCoreComponent : NSObject

- (void)registerInstallUpdateHandler:(void (^)(SPUInstallUpdateStatus))installUpdateHandler;
- (void)installUpdateWithChoice:(SPUInstallUpdateStatus)choice;

- (void)registerUpdateCheckStatusHandler:(void (^)(SPUUserInitiatedCheckStatus))updateCheckStatusCompletion;
- (void)cancelUpdateCheckStatus;
- (void)completeUpdateCheckStatus;

- (void)registerDownloadStatusHandler:(void (^)(SPUDownloadUpdateStatus))downloadUpdateStatusCompletion;
- (void)cancelDownloadStatus;
- (void)completeDownloadStatus;

- (void)registerAcknowledgement:(void (^)(void))acknowledgement;
- (void)acceptAcknowledgement;

- (void)dismissUpdateInstallation;

@end
