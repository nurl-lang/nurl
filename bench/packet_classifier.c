// benchmark-contract: branch-lcg32;seed=123456789;iterations=25000000;threshold=2147483648
#include <inttypes.h>
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
  const uint64_t iterations = 25000000ULL;
  const uint64_t threshold = 1ULL << 31;
  uint64_t state = 123456789ULL;
  uint64_t i = 0;

  while (i < iterations) {
    if (state < threshold) {
      state = (state * 1664525ULL + 1013904223ULL) & 0xffffffffULL;
    } else {
      state = (state * 22695477ULL + 1ULL) & 0xffffffffULL;
    }
    ++i;
  }

  emit_checksum(state);
  return 0;
}
