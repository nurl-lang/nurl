// benchmark-contract: lcg32;seed=123456789;iterations=50000000;mul=1664525;add=1013904223
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

static inline void verify_checksum(uint64_t value) {
#ifdef BENCH_VERIFY
  fwrite(&value, sizeof(value), 1, stdout);
#else
  (void)value;
#endif
}

int main(void) {
  const uint64_t iterations = 50000000ULL;
  uint64_t state = 123456789ULL;
  uint64_t i = 0;

  while (i < iterations) {
    state = (state * 1664525ULL + 1013904223ULL) & 0xffffffffULL;
    ++i;
  }

  verify_checksum(state);
  return (int)(state & 0x7fULL);
}
