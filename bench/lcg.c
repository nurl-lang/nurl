// benchmark-contract: lcg64-mmix;seed=1;iterations=100000000;mul=6364136223846793005;add=1442695040888963407
//
// lcg — 100M iterations of the MMIX linear congruential generator. One
// 64-bit multiply and one add per step, each depending on the previous
// result, so the loop cannot be folded into a closed form.
//
// Contract: the process prints exactly one line — the final state as a
// signed 64-bit integer, matching the peers that have no unsigned type.
#include <stdint.h>
#include <stdio.h>

int main(void) {
  // Unsigned arithmetic so the wrap-around is defined; the printed value
  // is the same bit pattern read as int64, which is what NURL, Rust,
  // Python and Node print.
  uint64_t x = 1;
  for (uint64_t i = 0; i < 100000000ULL; ++i) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
  }
  printf("%lld\n", (long long)(int64_t)x);
  return 0;
}
