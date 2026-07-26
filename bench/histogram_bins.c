// benchmark-contract: histogram;seed=123456789;iterations=20000000;bins=64;index=state&63
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
  const uint64_t iterations = 20000000ULL;
  uint64_t state = 123456789ULL;
  uint64_t bins[64] = {0};

  uint64_t i = 0;
  while (i < iterations) {
    state = (state * 1664525ULL + 1013904223ULL) & 0xffffffffULL;
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
  verify_checksum(checksum);
  return (int)(checksum & 0x7fULL);
}
