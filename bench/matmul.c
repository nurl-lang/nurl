// benchmark-contract: matmul-int;n=256;a=(i*N+j)%7;b=(i+j)%5;output=trace
//
// matmul — multiply two 256x256 integer matrices and print the trace of
// the product. Deterministic fill: A[i][j] = (i*N+j) % 7,
// B[i][j] = (i+j) % 5. Triple-nested loop over flat arrays: index
// arithmetic and the column-strided read of B dominate.
//
// Contract: the process prints exactly one line — the trace.
#include <stdio.h>
#include <stdlib.h>

int main(void) {
  const int n = 256;
  long long* a = (long long*)malloc((size_t)n * n * sizeof(long long));
  long long* b = (long long*)malloc((size_t)n * n * sizeof(long long));
  long long* c = (long long*)malloc((size_t)n * n * sizeof(long long));
  if (a == NULL || b == NULL || c == NULL) {
    return 1;
  }

  for (int i = 0; i < n; ++i) {
    for (int j = 0; j < n; ++j) {
      int idx = i * n + j;
      a[idx] = idx % 7;
      b[idx] = (i + j) % 5;
      c[idx] = 0;
    }
  }

  for (int ri = 0; ri < n; ++ri) {
    for (int cj = 0; cj < n; ++cj) {
      long long s = 0;
      for (int k = 0; k < n; ++k) {
        s += a[ri * n + k] * b[k * n + cj];
      }
      c[ri * n + cj] = s;
    }
  }

  long long tr = 0;
  for (int d = 0; d < n; ++d) {
    tr += c[d * n + d];
  }

  printf("%lld\n", tr);
  free(a);
  free(b);
  free(c);
  return 0;
}
