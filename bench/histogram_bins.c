// benchmark-contract: histogram-xs13;seed=123456789;iterations=20000000;bins=64;index=state&63;xorshift=13
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
  const uint64_t iterations = 20000000ULL;
  uint64_t state = 123456789ULL;
  uint64_t bins[64] = {0};

  uint64_t i = 0;
  while (i < iterations) {
    state = (state * 1664525ULL + 1013904223ULL) & 0xffffffffULL;
    state ^= state >> 13;
    uint64_t index = state & 63ULL;
    bins[index] += 1ULL;
    ++i;
  }

  uint64_t checksum = state;
  uint64_t index = 0;
  while (index < 64ULL) {
    checksum ^= bins[index] * (index + 1ULL);
    ++index;
  }
  emit_checksum(checksum);
  return 0;
}
