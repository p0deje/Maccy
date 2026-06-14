#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MaccyTextProcessor : NSObject

+ (NSUInteger)validUTF8PrefixLengthInData:(NSData *)data
                                  maxBytes:(NSUInteger)maxBytes NS_SWIFT_NAME(validUTF8PrefixLength(in:maxBytes:));
+ (uint64_t)fingerprintForData:(NSData *)data NS_SWIFT_NAME(fingerprint(for:));

@end

NS_ASSUME_NONNULL_END
