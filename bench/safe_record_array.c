// benchmark-contract: safe-record-array;records=4096;record=4xu64(key,val,hits,tag);steps=10000000;lcg=mmix(seed=1);draw=state>>33;ia=r&4095;ib=(r>>12)&4095;swap=(r>>24)&1;fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// safe_record_array — 10M by-value updates of an array of 4096 small
// records (see safe_record_array.nu for the shape). An array of structs;
// `mix` and `bump` take and return their records by value, exactly as
// the NURL and Rust peers do. C has no bounds checks, so this column is
// the floor the two safe languages' checked indexing is measured
// against.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

typedef struct { uint64_t key, val, hits, tag; } Rec;
typedef struct { uint64_t lo, hi; } Pair;

static Pair mix(Rec a, Rec b, uint64_t r) {
  Pair p = { a.key ^ b.val ^ r, (a.val + b.key) * 2654435761ULL };
  return p;
}

static Rec bump(Rec a, Pair p) {
  Rec o = { a.key ^ p.lo, a.val + (p.hi >> 3), a.hits + 1, (a.tag + (p.lo & 15)) & 255 };
  return o;
}

static uint64_t fnv(uint64_t h, uint64_t v) { return (h ^ v) * 1099511628211ULL; }

int main(void) {
  const uint64_t steps = 10000000ULL * BENCH_SCALE;
  const int n = 4096;
  Rec *recs = malloc(sizeof(Rec) * n);
  if (!recs) return 1;
  for (int z = 0; z < n; ++z) {
    uint64_t zu = (uint64_t)z;
    Rec r = { zu * 2654435761ULL, zu, 0, zu & 7 };
    recs[z] = r;
  }

  uint64_t x = 1;
  for (uint64_t k = 0; k < steps; ++k) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    uint64_t r = x >> 33;
    size_t ia = r & 4095, ib = (r >> 12) & 4095;
    Rec a = recs[ia];
    Rec b = recs[ib];
    Pair p = mix(a, b, r);
    recs[ia] = bump(a, p);
    if (((r >> 24) & 1) == 1) {
      Rec t = recs[ia];
      Rec w = recs[ib];
      recs[ia] = w;
      recs[ib] = t;
    }
  }

  uint64_t h = 1469598103934665603ULL;
  for (int q = 0; q < n; ++q) {
    Rec e = recs[q];
    h = fnv(h, e.key);
    h = fnv(h, e.val);
    h = fnv(h, e.hits);
    h = fnv(h, e.tag);
  }
  h = fnv(h, x);
  free(recs);
  printf("%lld\n", (long long)(h & 0x7fffffffffffffffULL));
  return 0;
}
