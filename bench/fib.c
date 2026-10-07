// benchmark-contract: fib-naive;n=35
//
// fib — naive double-recursive Fibonacci(35), no memoisation: ~29.8M
// source-level evaluations, ~15M executed calls after LLVM turns the
// second recursive branch into a loop (same transform in every
// compiled peer). The call/return path is the whole benchmark.
//
// Contract: the process prints exactly one line — fib(35) = 9227465.
#include <stdio.h>

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

static long long fib(long long n) {
  if (n < 2) {
    return n;
  }
  return fib(n - 1) + fib(n - 2);
}

int main(void) {
  // BENCH_SCALE calls of fib(35), summed. The argument is 35 + (total >> 62):
  // always 35, but not provably constant, so the call cannot be hoisted.
  long long total = 0;
  for (unsigned long long rep = 0; rep < BENCH_SCALE; ++rep) {
    total += fib(35 + (total >> 62));
  }
  printf("%lld\n", total);
  return 0;
}
