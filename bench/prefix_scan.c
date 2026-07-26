// benchmark-contract: prefix-scan;seed=123456789;batches=1000000;width=16;value-mask=65535
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
  const uint64_t batches = 1000000ULL;
  uint64_t values[16] = {0};
  uint64_t state = 123456789ULL;
  uint64_t checksum = 0;
  uint64_t batch = 0;

  while (batch < batches) {
    uint64_t index = 0;
    while (index < 16ULL) {
      state = (state * 1664525ULL + 1013904223ULL) & 0xffffffffULL;
      values[index] = state & 0xffffULL;
      ++index;
    }

    index = 1;
    while (index < 16ULL) {
      values[index] += values[index - 1ULL];
      ++index;
    }
    checksum ^= values[15];
    ++batch;
  }

  uint64_t result = state ^ checksum;
  emit_checksum(result);
  return 0;
}
