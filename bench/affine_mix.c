// benchmark-contract: affine-mix-xs9;seed=123456789;iterations=20000000;mask=0x03ffffffffffffff;xorshift=9
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
  uint64_t state = 123456789ULL;
  uint64_t i = 0;

  while (i < iterations) {
    state = ((state << 3) + i) & 0x03ffffffffffffffULL;
    state ^= state >> 9;
    state = ((state << 2) - 3ULL) & 0x03ffffffffffffffULL;
    ++i;
  }

  emit_checksum(state);
  return 0;
}
