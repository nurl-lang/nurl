// benchmark-contract: ring-write;seed=123456789;iterations=20000000;words=64;value=state32x2
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
  const uint64_t iterations = 20000000ULL;
  const uint64_t mask = 63ULL;
  uint64_t buf[64] = {0};
  uint64_t state = 123456789ULL;
  uint64_t i = 0;

  while (i < iterations) {
    state = (state * 1664525ULL + 1013904223ULL) & 0xffffffffULL;
    buf[i & mask] = (state << 32) | state;
    ++i;
  }

  uint64_t result = ((state << 32) | state) ^ buf[0];
  emit_checksum(result);
  return 0;
}
