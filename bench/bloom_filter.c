// benchmark-contract: bloom-filter;seed=123456789;build=10000;queries=1000000;words=256;lanes=4
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

static inline uint64_t lcg_step(uint64_t* state) {
  *state = ((*state) * 1664525ULL + 1013904223ULL) & 0xffffffffULL;
  return *state;
}

static inline void split_block_insert(uint64_t filter[256], uint64_t hash) {
  for (uint64_t lane = 0; lane < 4; ++lane) {
    uint64_t word = (hash >> (lane * 8ULL)) & 255ULL;
    uint64_t bit = (hash >> (lane * 11ULL + 3ULL)) & 63ULL;
    filter[word] |= 1ULL << bit;
  }
}

static inline uint64_t split_block_maybe_contains(const uint64_t filter[256], uint64_t hash) {
  uint64_t hit = 1ULL;
  for (uint64_t lane = 0; lane < 4; ++lane) {
    uint64_t word = (hash >> (lane * 8ULL)) & 255ULL;
    uint64_t bit = (hash >> (lane * 11ULL + 3ULL)) & 63ULL;
    hit &= (filter[word] >> bit) & 1ULL;
  }
  return hit;
}

int main(void) {
  uint64_t state = 123456789ULL;
  uint64_t filter[256] = {0};

  for (uint64_t i = 0; i < 10000ULL; ++i) {
    uint64_t h = (lcg_step(&state) << 32) | lcg_step(&state);
    split_block_insert(filter, h);
  }

  uint64_t hits = 0;
  for (uint64_t i = 0; i < 1000000ULL; ++i) {
    uint64_t h = (lcg_step(&state) << 32) | lcg_step(&state);
    hits += split_block_maybe_contains(filter, h);
  }

  verify_checksum(hits);
  return (int)(hits & 0x7fULL);
}
