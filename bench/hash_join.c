// benchmark-contract: hash-join;seed=123456789;build=160;queries=5000000;cap=256;bloom=64;group=16;probe=alternating-built-random
#include <stdbool.h>
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

enum {
  CAP = 256,
  BLOOM_WORDS = 64,
  GROUP = 16,
  COMPACT_CHUNK = 64,
  BUILD_ROWS = 160,
};

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

static inline uint64_t fp7(uint64_t key) { return ((key >> 57) & 0x7fULL) + 1ULL; }

static inline void bloom_add(uint64_t bloom[BLOOM_WORDS], uint64_t h) {
  for (uint64_t lane = 0; lane < 4; ++lane) {
    uint64_t bit_idx = (h >> (lane * 13)) & 4095ULL;
    uint64_t word = bit_idx >> 6;
    uint64_t bit = bit_idx & 63ULL;
    bloom[word] |= 1ULL << bit;
  }
}

static inline bool bloom_maybe(const uint64_t bloom[BLOOM_WORDS], uint64_t h) {
  for (uint64_t lane = 0; lane < 4; ++lane) {
    uint64_t bit_idx = (h >> (lane * 13)) & 4095ULL;
    uint64_t word = bit_idx >> 6;
    uint64_t bit = bit_idx & 63ULL;
    if (((bloom[word] >> bit) & 1ULL) == 0ULL) {
      return false;
    }
  }
  return true;
}

static inline void grouped_insert(uint64_t ctrl[CAP], uint64_t keys[CAP], uint64_t vals[CAP],
                                  uint64_t key, uint64_t val, bool partitioned) {
  uint64_t fp = fp7(key);
  uint64_t part = (key >> 62) & 3ULL;
  uint64_t group = partitioned ? ((key & 63ULL) & 48ULL) : ((key & 255ULL) & 240ULL);
  uint64_t rounds = partitioned ? 4ULL : 16ULL;

  for (uint64_t r = 0; r < rounds; ++r) {
    for (uint64_t lane = 0; lane < GROUP; ++lane) {
      uint64_t idx = partitioned ? ((part << 6) | ((group + lane) & 63ULL))
                                 : ((group + lane) & 255ULL);
      uint64_t c = ctrl[idx];
      if (c == 0ULL) {
        ctrl[idx] = fp;
        keys[idx] = key;
        vals[idx] = val;
        return;
      }
      if (c == fp && keys[idx] == key) {
        vals[idx] = val;
        return;
      }
    }
    group = partitioned ? ((group + GROUP) & 63ULL) : ((group + GROUP) & 255ULL);
  }

  uint64_t idx = partitioned ? ((part << 6) | (key & 63ULL)) : (key & 255ULL);
  uint64_t limit = partitioned ? 64ULL : 256ULL;
  for (uint64_t i = 0; i < limit; ++i) {
    uint64_t c = ctrl[idx];
    if (c == 0ULL || (c == fp && keys[idx] == key)) {
      ctrl[idx] = fp;
      keys[idx] = key;
      vals[idx] = val;
      return;
    }
    idx = partitioned ? ((part << 6) | ((idx + 1ULL) & 63ULL)) : ((idx + 1ULL) & 255ULL);
  }
}

static inline int grouped_probe(const uint64_t ctrl[CAP], const uint64_t keys[CAP],
                                const uint64_t vals[CAP], uint64_t probe_key,
                                bool partitioned, uint64_t* out_val) {
  uint64_t fp = fp7(probe_key);
  uint64_t part = (probe_key >> 62) & 3ULL;
  uint64_t group = partitioned ? ((probe_key & 63ULL) & 48ULL)
                               : ((probe_key & 255ULL) & 240ULL);
  uint64_t rounds = partitioned ? 4ULL : 16ULL;

  for (uint64_t r = 0; r < rounds; ++r) {
    for (uint64_t lane = 0; lane < GROUP; ++lane) {
      uint64_t idx = partitioned ? ((part << 6) | ((group + lane) & 63ULL))
                                 : ((group + lane) & 255ULL);
      uint64_t c = ctrl[idx];
      if (c == 0ULL) {
        return 0;
      }
      if (c == fp && keys[idx] == probe_key) {
        *out_val = vals[idx];
        return 1;
      }
    }
    group = partitioned ? ((group + GROUP) & 63ULL) : ((group + GROUP) & 255ULL);
  }

  return 0;
}

int main(void) {
  uint64_t state = 123456789ULL;
  uint64_t ctrl[CAP] = {0};
  uint64_t keys[CAP] = {0};
  uint64_t vals[CAP] = {0};
  uint64_t reducer_bloom[BLOOM_WORDS] = {0};
  uint64_t compact[COMPACT_CHUNK] = {0};
  uint64_t built_keys[BUILD_ROWS] = {0};

  const uint64_t build_rows = BUILD_ROWS;
  const uint64_t total_queries = 5000000ULL;
  const bool use_partitioned = (build_rows >= 128ULL) && (total_queries >= 200000ULL);

  for (uint64_t i = 0; i < build_rows; ++i) {
    uint64_t key = draw64(&state);
    uint64_t val = draw64(&state);
    built_keys[i] = key;
    bloom_add(reducer_bloom, key);
    grouped_insert(ctrl, keys, vals, key, val, use_partitioned);
  }

  uint64_t sum = 0;
  uint64_t compact_len = 0;
  for (uint64_t i = 0; i < total_queries; ++i) {
    // Every query draws two LCG words so the stream advances identically
    // whichever side of the branch it takes; even queries then replace the
    // drawn key with one that was actually built. Without that, a random
    // 64-bit probe key never matches a 160-row table and the benchmark
    // measures nothing but the Bloom filter's reject path — which is what
    // the all-zero checksum in the pre-2026-07 reports was telling us.
    uint64_t drawn_high = lcg_step(&state);
    uint64_t drawn_low = lcg_step(&state);
    uint64_t probe_key = ((i & 1ULL) == 0ULL) ? built_keys[(i >> 1) % build_rows]
                                              : ((drawn_high << 32) | drawn_low);
    if (!bloom_maybe(reducer_bloom, probe_key)) {
      continue;
    }

    uint64_t v = 0;
    if (grouped_probe(ctrl, keys, vals, probe_key, use_partitioned, &v)) {
      compact[compact_len++] = v;
      if (compact_len == COMPACT_CHUNK) {
        for (uint64_t j = 0; j < COMPACT_CHUNK; ++j) {
          sum ^= compact[j];
        }
        compact_len = 0;
      }
    }
  }

  for (uint64_t j = 0; j < compact_len; ++j) {
    sum ^= compact[j];
  }

  emit_checksum(sum);
  return 0;
}
