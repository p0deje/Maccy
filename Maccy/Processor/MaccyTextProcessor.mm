#import "MaccyTextProcessor.h"

#include "ClipboardByteProcessor.hpp"

@implementation MaccyTextProcessor

+ (NSUInteger)validUTF8PrefixLengthInData:(NSData *)data maxBytes:(NSUInteger)maxBytes {
  return maccy::processor::validUTF8PrefixLength(
    static_cast<const std::uint8_t *>(data.bytes),
    data.length,
    maxBytes
  );
}

+ (uint64_t)fingerprintForData:(NSData *)data {
  return maccy::processor::fnv1a64(
    static_cast<const std::uint8_t *>(data.bytes),
    data.length
  );
}

@end
