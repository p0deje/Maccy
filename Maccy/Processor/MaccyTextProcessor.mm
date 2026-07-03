#import "MaccyTextProcessor.h"

#include "ClipboardByteProcessor.hpp"

// Fixed seed for xxh3. It MUST be a compile-time constant (not per-process
// random) so the persisted HistoryItemContent.fingerprint column stays valid
// across launches — a random seed would invalidate every stored fingerprint on
// restart. Seed 0 is a fixed, well-defined xxh3 seed.
namespace {
constexpr std::uint64_t kMaccyHashSeed = 0;
}

@implementation MaccyTextProcessor

+ (NSUInteger)validUTF8PrefixLengthInData:(NSData *)data maxBytes:(NSUInteger)maxBytes {
  // DEBUG-only enforcement of the NSData contract this bridge relies on:
  // `bytes` is non-NULL iff `length > 0`. The C++ side never dereferences past
  // `length`, so the only dangerous case is a non-zero length with a NULL
  // pointer — caught here in debug builds.
  NSCAssert(data.bytes != NULL || data.length == 0,
            @"NSData contract violated: bytes is NULL with a non-zero length");
  return maccy::processor::validUTF8PrefixLength(
    static_cast<const std::uint8_t *>(data.bytes),
    data.length,
    maxBytes
  );
}

+ (uint64_t)fingerprintForData:(NSData *)data {
  // xxh3 (formerly FNV-1a): SIMD-friendly, ~3-5× throughput. xxh3_64 defines
  // empty input (length 0 → a fixed hash, no dereference), and `data.bytes` is
  // non-NULL only when `length > 0` (NSData contract). No separate empty guard
  // is needed; the DEBUG assert below enforces the contract the bridge relies
  // on. The seed is the fixed kMaccyHashSeed above.
  NSCAssert(data.bytes != NULL || data.length == 0,
            @"NSData contract violated: bytes is NULL with a non-zero length");
  return maccy::processor::xxh3_64(
    static_cast<const std::uint8_t *>(data.bytes),
    data.length,
    kMaccyHashSeed
  );
}

@end
