#pragma once

#include <cstddef>
#include <cstdint>

namespace maccy {
namespace processor {

std::size_t validUTF8PrefixLength(const std::uint8_t *bytes, std::size_t count, std::size_t maxBytes) noexcept;
std::uint64_t fnv1a64(const std::uint8_t *bytes, std::size_t count) noexcept;
// BS-8 (08-O-007): SIMD-friendly hash for the dedup fingerprint, replacing the
// serial FNV-1a (~25-35 GB/s vs FNV's ~1 GB/s). `seed` is the fixed migration
// seed (see step-8 §8.5 — it MUST be constant so the persisted
// HistoryItemContent.fingerprint column is stable across launches). FNV above
// is retained only for migration-period diagnostics, not as a fallback key.
std::uint64_t xxh3_64(const std::uint8_t *bytes, std::size_t count, std::uint64_t seed) noexcept;

} // namespace processor
} // namespace maccy
