// benchmark-contract: bloom-filter;seed=123456789;build=10000;queries=4000000;words=256;lanes=4
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

static inline uint64_t lcg_step(uint64_t* state) {
  *state = ((*state) * 1664525ULL + 1013904223ULL) & 0xffffffffULL;
  return *state;
}

static inline uint64_t draw64(uint64_t* state) {
  // Two calls sequenced by hand: the order of the two `lcg_step` calls
  // inside one expression is unspecified in C, and the peers (Rust,
  // NURL, Python, Node) all draw high first. Same stream, no
  // compiler-dependent checksum.
  uint64_t high = lcg_step(state);
  uint64_t low = lcg_step(state);
  return (high << 32) | low;
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
    uint64_t h = draw64(&state);
    split_block_insert(filter, h);
  }

  uint64_t hits = 0;
  for (uint64_t i = 0; i < 4000000ULL; ++i) {
    uint64_t h = draw64(&state);
    hits += split_block_maybe_contains(filter, h);
  }

  emit_checksum(hits);
  return 0;
}
