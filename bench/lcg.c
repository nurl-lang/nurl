// benchmark-contract: lcg64-mmix-xs33;seed=1;iterations=20000000;mul=6364136223846793005;add=1442695040888963407;xorshift=33
//
// lcg — 20M iterations of the MMIX linear congruential generator with a
// PCG-style xorshift mix folded into the state each step. A bare LCG is
// an affine recurrence, and LLVM's unroller composes k affine steps
// into one (x·aᵏ + cₖ), so a bare-LCG row measures the compiler's
// composition factor rather than the chain. The xor of a shifted copy
// breaks affinity: no number of steps composes, every step's multiply,
// add, shift and xor stay on the critical path.
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
  for (uint64_t i = 0; i < 20000000ULL; ++i) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    x ^= x >> 33;
  }
  printf("%lld\n", (long long)(int64_t)x);
  return 0;
}
