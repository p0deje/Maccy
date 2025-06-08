//
//  SUAppcast.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUAPPCAST_H
#define SUAPPCAST_H

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

@class SUAppcastItem;

/**
 The appcast representing a collection of `SUAppcastItem` items in the feed.
 */
SU_EXPORT @interface SUAppcast : NSObject

- (instancetype)init NS_UNAVAILABLE;

/**
 The collection of update items.
 
 These `SUAppcastItem` items are in the same order as specified in the appcast XML feed and are thus not sorted by version.
 */
@property (readonly, nonatomic, copy) NSArray<SUAppcastItem *> *items;

@end

NS_ASSUME_NONNULL_END

#endif
