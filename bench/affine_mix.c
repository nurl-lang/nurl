// benchmark-contract: affine-mix;seed=123456789;iterations=50000000;mask=0x03ffffffffffffff
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
    state = ((state << 3) + i) & 0x03ffffffffffffffULL;
    state = ((state << 2) - 3ULL) & 0x03ffffffffffffffULL;
    ++i;
  }

  verify_checksum(state);
  return (int)(state & 0x7fULL);
}
