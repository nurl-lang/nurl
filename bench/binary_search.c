// benchmark-contract: binary-search;seed=123456789;queries=5000000;values=even-0..126;algorithm=lower-bound
#include <stdint.h>
#include <stdio.h>

static inline void emit_checksum(uint64_t value) {
  // Every peer prints this one line and nothing else; the 63-bit mask
  // keeps the value printable by the languages without unsigned 64-bit
  // integers (NURL's `i`, Python's signed int, JS BigInt) so the five
  // outputs can be compared byte for byte.
  printf("%llu\n", (unsigned long long)(value & 0x7fffffffffffffffULL));
}

int main(void) {
  const uint64_t iterations = 5000000ULL;
  const uint64_t values[64] = {
      0ULL,   2ULL,   4ULL,   6ULL,   8ULL,   10ULL,  12ULL,  14ULL,
      16ULL,  18ULL,  20ULL,  22ULL,  24ULL,  26ULL,  28ULL,  30ULL,
      32ULL,  34ULL,  36ULL,  38ULL,  40ULL,  42ULL,  44ULL,  46ULL,
      48ULL,  50ULL,  52ULL,  54ULL,  56ULL,  58ULL,  60ULL,  62ULL,
      64ULL,  66ULL,  68ULL,  70ULL,  72ULL,  74ULL,  76ULL,  78ULL,
      80ULL,  82ULL,  84ULL,  86ULL,  88ULL,  90ULL,  92ULL,  94ULL,
      96ULL,  98ULL,  100ULL, 102ULL, 104ULL, 106ULL, 108ULL, 110ULL,
      112ULL, 114ULL, 116ULL, 118ULL, 120ULL, 122ULL, 124ULL, 126ULL,
  };

  uint64_t state = 123456789ULL;
  uint64_t hits = 0;
  uint64_t i = 0;
  while (i < iterations) {
    state = (state * 1664525ULL + 1013904223ULL) & 0xffffffffULL;
    uint64_t target = state & 127ULL;
    uint64_t low = 0;
    uint64_t high = 64;
    while (low < high) {
      uint64_t middle = low + ((high - low) >> 1);
      if (values[middle] < target) {
        low = middle + 1ULL;
      } else {
        high = middle;
      }
    }
    if (low < 64ULL && values[low] == target) {
      hits += 1ULL;
    }
    ++i;
  }

  uint64_t checksum = state ^ hits;
  emit_checksum(checksum);
  return 0;
}
