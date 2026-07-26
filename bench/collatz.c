// benchmark-contract: collatz-longest;starts=1..99999
//
// collatz — the longest Collatz chain for any start below 100,000
// (= 350 steps). A hot while loop whose branch depends on the low bit
// of a value the compiler cannot predict, and no array at all.
//
// Contract: the process prints exactly one line — the longest chain.
#include <stdio.h>

static long long steps(long long n) {
  long long c = 0;
  while (n > 1) {
    n = (n % 2 == 0) ? n / 2 : 3 * n + 1;
    ++c;
  }
  return c;
}

int main(void) {
  long long best = 0;
  for (long long k = 1; k < 100000; ++k) {
    long long s = steps(k);
    if (s > best) {
      best = s;
    }
  }
  printf("%lld\n", best);
  return 0;
}
