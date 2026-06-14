#include "ClipboardByteProcessor.hpp"

#include <algorithm>

namespace {

constexpr std::uint64_t fnvOffsetBasis = 14695981039346656037ULL;
constexpr std::uint64_t fnvPrime = 1099511628211ULL;

bool continuation(std::uint8_t byte) {
  return (byte & 0xC0) == 0x80;
}

} // namespace

namespace maccy {
namespace processor {

std::size_t validUTF8PrefixLength(const std::uint8_t *bytes, std::size_t count, std::size_t maxBytes) {
  const std::size_t limit = std::min(count, maxBytes);
  std::size_t index = 0;
  std::size_t lastValid = 0;

  while (index < limit) {
    const std::uint8_t first = bytes[index];

    if (first < 0x80) {
      ++index;
      lastValid = index;
      continue;
    }

    std::size_t width = 0;
    std::uint32_t codepoint = 0;
    std::uint32_t minimum = 0;

    if ((first & 0xE0) == 0xC0) {
      width = 2;
      codepoint = first & 0x1F;
      minimum = 0x80;
    } else if ((first & 0xF0) == 0xE0) {
      width = 3;
      codepoint = first & 0x0F;
      minimum = 0x800;
    } else if ((first & 0xF8) == 0xF0) {
      width = 4;
      codepoint = first & 0x07;
      minimum = 0x10000;
    } else {
      break;
    }

    if (index + width > limit) {
      break;
    }

    bool valid = true;
    for (std::size_t offset = 1; offset < width; ++offset) {
      const std::uint8_t next = bytes[index + offset];
      if (!continuation(next)) {
        valid = false;
        break;
      }
      codepoint = (codepoint << 6) | (next & 0x3F);
    }

    if (!valid || codepoint < minimum || codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF)) {
      break;
    }

    index += width;
    lastValid = index;
  }

  return lastValid;
}

std::uint64_t fnv1a64(const std::uint8_t *bytes, std::size_t count) {
  std::uint64_t hash = fnvOffsetBasis;
  for (std::size_t index = 0; index < count; ++index) {
    hash ^= bytes[index];
    hash *= fnvPrime;
  }
  return hash;
}

} // namespace processor
} // namespace maccy
