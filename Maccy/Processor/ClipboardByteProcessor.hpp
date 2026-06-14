#pragma once

#include <cstddef>
#include <cstdint>

namespace maccy {
namespace processor {

std::size_t validUTF8PrefixLength(const std::uint8_t *bytes, std::size_t count, std::size_t maxBytes);
std::uint64_t fnv1a64(const std::uint8_t *bytes, std::size_t count);

} // namespace processor
} // namespace maccy
