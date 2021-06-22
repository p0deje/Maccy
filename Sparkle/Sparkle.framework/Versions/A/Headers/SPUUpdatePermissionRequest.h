//
//  SPUUpdatePermissionRequest.h
//  Sparkle
//
//  Created by Mayur Pawashe on 8/14/16.
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
#import <Sparkle/SUExport.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 This class represents information needed to make a permission request for checking updates.
 */
SU_EXPORT @interface SPUUpdatePermissionRequest : NSObject<NSSecureCoding>

/*!
 Initializes a new update permission request instance.
 
 @param systemProfile The system profile information.
 */
- (instancetype)initWithSystemProfile:(NSArray<NSDictionary<NSString *, NSString *> *> *)systemProfile;

/*!
 A read-only property for the user's system profile.
 */
@property (nonatomic, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *systemProfile;

@end

NS_ASSUME_NONNULL_END
