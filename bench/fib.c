// benchmark-contract: fib-naive;n=35
//
// fib — naive double-recursive Fibonacci(35), no memoisation: ~29.8M
// source-level evaluations, ~15M executed calls after LLVM turns the
// second recursive branch into a loop (same transform in every
// compiled peer). The call/return path is the whole benchmark.
//
// Contract: the process prints exactly one line — fib(35) = 9227465.
#include <stdio.h>

static long long fib(long long n) {
  if (n < 2) {
    return n;
  }
  return fib(n - 1) + fib(n - 2);
}

int main(void) {
  printf("%lld\n", fib(35));
  return 0;
}
