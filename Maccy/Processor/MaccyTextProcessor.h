#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridge between Swift and the C++ byte processors in `ClipboardByteProcessor`.
@interface MaccyTextProcessor : NSObject

/// Length of the longest valid UTF-8 prefix of `data`, capped at `maxBytes`.
+ (NSUInteger)validUTF8PrefixLengthInData:(NSData *)data
                                  maxBytes:(NSUInteger)maxBytes NS_SWIFT_NAME(validUTF8PrefixLength(in:maxBytes:));

/// Stable xxh3 64-bit dedup fingerprint of `data`.
+ (uint64_t)fingerprintForData:(NSData *)data NS_SWIFT_NAME(fingerprint(for:));

@end

NS_ASSUME_NONNULL_END
