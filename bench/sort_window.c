// benchmark-contract: sort-window;seed=123456789;iterations=5000000;width=8;algorithm=bubble
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

static inline void bubble_sort8(uint64_t arr[8]) {
  for (unsigned pass = 0; pass < 8; ++pass) {
    for (unsigned j = 0; j + 1 < 8 - pass; ++j) {
      if (arr[j] > arr[j + 1]) {
        uint64_t tmp = arr[j];
        arr[j] = arr[j + 1];
        arr[j + 1] = tmp;
      }
    }
  }
}

int main(void) {
  const uint64_t iterations = 5000000ULL;
  uint64_t state = 123456789ULL;
  uint64_t i = 0;
  uint64_t window[8] = {0ULL, 1ULL, 2ULL, 3ULL, 4ULL, 5ULL, 6ULL, 7ULL};

  while (i < iterations) {
    state = (state * 1664525ULL + 1013904223ULL) & 0xffffffffULL;

    window[0] = state;
    window[1] = state ^ 0xa5a5a5a5ULL;
    window[2] = (state + i) & 0xffffffffULL;
    window[3] = state * 3ULL;
    window[4] = (state - i) & 0xffffffffULL;
    window[5] = state >> 3;
    window[6] = state << 1;
    window[7] = (state + 7ULL) & 0xffffffffULL;

    bubble_sort8(window);
    state = state ^ window[0] ^ window[7];
    ++i;
  }

  verify_checksum(state);
  return (int)(state & 0x7fULL);
}
