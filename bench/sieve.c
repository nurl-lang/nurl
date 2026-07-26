// benchmark-contract: sieve-eratosthenes;limit=10000000;marks=byte-array
//
// sieve — Sieve of Eratosthenes over a 10 MB byte array, then a scan
// that counts the primes below 10,000,000 (= 664,579). Irregular-stride
// writes followed by one linear read: memory bandwidth and branch
// prediction rather than ALU throughput.
//
// Contract: the process prints exactly one line — the prime count.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
  const int n = 10000000;
  unsigned char* mark = (unsigned char*)malloc((size_t)n);
  if (mark == NULL) {
    return 1;
  }
  memset(mark, 0, (size_t)n);
  mark[0] = 1;
  mark[1] = 1;

  for (long long p = 2; p * p < n; ++p) {
    if (mark[p] == 0) {
      for (long long m = p * p; m < n; m += p) {
        mark[m] = 1;
      }
    }
  }

  long long count = 0;
  for (int k = 2; k < n; ++k) {
    if (mark[k] == 0) {
      ++count;
    }
  }

  printf("%lld\n", count);
  free(mark);
  return 0;
}
