// benchmark-contract: ring-write;seed=123456789;iterations=50000000;words=64;value=state32x2
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
  verify_checksum(result);
  return (int)(result & 0x7fULL);
}
