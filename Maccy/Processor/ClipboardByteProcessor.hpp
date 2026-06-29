#pragma once

#include <cstddef>
#include <cstdint>

namespace maccy {
namespace processor {

/// Length of the longest valid UTF-8 prefix of `bytes[0..count)`, capped at
/// `maxBytes`. Stops at the first malformed byte or truncated sequence.
std::size_t validUTF8PrefixLength(const std::uint8_t *bytes, std::size_t count, std::size_t maxBytes) noexcept;

/// FNV-1a 64-bit hash of `bytes[0..count)`. Retained only for migration-period
/// diagnostics, not as a fallback dedup key.
std::uint64_t fnv1a64(const std::uint8_t *bytes, std::size_t count) noexcept;

/// xxh3 64-bit hash of `bytes[0..count)` — a SIMD-friendly replacement for the
/// serial FNV-1a used for the dedup fingerprint (~25-35 GB/s vs FNV's ~1 GB/s).
///
/// `seed` MUST be a compile-time constant (not per-process random) so the
/// persisted `HistoryItemContent.fingerprint` column stays valid across launches.
/// Empty input is well-defined (unlike FNV's offset basis); backfilling legacy
/// rows must account for the change in empty-input behavior.
std::uint64_t xxh3_64(const std::uint8_t *bytes, std::size_t count, std::uint64_t seed) noexcept;

} // namespace processor
} // namespace maccy
