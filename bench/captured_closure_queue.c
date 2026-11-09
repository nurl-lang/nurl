// benchmark-contract: captured-closure-queue;slots=16;kinds=5(add,mulxor,rotadd,table16,pair);steps=10000000;lcg=mmix(seed=1);draw=state>>33;slot=r&15;refill=every256th(slot=(r>>8)&15,kind=((r>>12)&65535)%5);chain=v=f(v^r);fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// captured_closure_queue — 10M calls through a queue of 16 closures with
// differently shaped captured environments (see captured_closure_queue.nu
// for the shape). C has no closures, so each one is spelled out as what
// the other two compile to: a { function pointer, environment pointer }
// pair, the environment malloc'd per closure and freed when its slot is
// refilled; the table kind's environment points at a separately
// malloc'd 16-entry table, as a captured Vec's buffer is separate from
// the Vec.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

typedef struct {
  uint64_t (*fn)(void *env, uint64_t x);
  void (*drop)(void *env);
  void *env;
} Clo;

static void *xmalloc(size_t n) {
  void *p = malloc(n);
  if (!p) abort();
  return p;
}

static void drop_plain(void *env) { free(env); }

typedef struct { uint64_t c; } EnvAdd;
static uint64_t fn_add(void *e, uint64_t x) { return x + ((EnvAdd *)e)->c; }
static Clo mk_add(uint64_t c) {
  EnvAdd *e = xmalloc(sizeof *e);
  e->c = c;
  return (Clo){ fn_add, drop_plain, e };
}

typedef struct { uint64_t m, s; } EnvMulXor;
static uint64_t fn_mulxor(void *e, uint64_t x) {
  EnvMulXor *p = e;
  return (x * p->m) ^ p->s;
}
static Clo mk_mulxor(uint64_t m, uint64_t s) {
  EnvMulXor *e = xmalloc(sizeof *e);
  e->m = m; e->s = s;
  return (Clo){ fn_mulxor, drop_plain, e };
}

typedef struct { uint64_t rot, a, b; } EnvRotAdd;
static uint64_t fn_rotadd(void *e, uint64_t x) {
  EnvRotAdd *p = e;
  return (((x >> p->rot) | (x << (64 - p->rot))) + p->a) ^ p->b;
}
static Clo mk_rotadd(uint64_t rot, uint64_t a, uint64_t b) {
  EnvRotAdd *e = xmalloc(sizeof *e);
  e->rot = rot; e->a = a; e->b = b;
  return (Clo){ fn_rotadd, drop_plain, e };
}

typedef struct { uint64_t *t; size_t len; } EnvTable;
static uint64_t fn_table(void *e, uint64_t x) {
  EnvTable *p = e;
  size_t j = x & 15;
  if (j >= p->len) abort();
  return x ^ p->t[j];
}
static void drop_table(void *env) {
  free(((EnvTable *)env)->t);
  free(env);
}
static Clo mk_table(uint64_t seed) {
  EnvTable *e = xmalloc(sizeof *e);
  e->t = xmalloc(16 * sizeof(uint64_t));
  e->len = 16;
  for (uint64_t j = 0; j < 16; ++j) e->t[j] = (seed ^ j) * 2654435761ULL + j;
  return (Clo){ fn_table, drop_table, e };
}

typedef struct { uint64_t lo, hi; } EnvPair;
static uint64_t fn_pair(void *e, uint64_t x) {
  EnvPair *p = e;
  return (x + p->lo) ^ p->hi;
}
static Clo mk_pair(uint64_t lo, uint64_t hi) {
  EnvPair *e = xmalloc(sizeof *e);
  e->lo = lo; e->hi = hi;
  return (Clo){ fn_pair, drop_plain, e };
}

// A closure of kind 0..4, its captures drawn from `r`.
static Clo make(uint64_t kind, uint64_t r) {
  if (kind == 0) return mk_add(r);
  if (kind == 1) return mk_mulxor(r | 1, r >> 5);
  if (kind == 2) return mk_rotadd((r & 31) + 1, r >> 7, r * 3);
  if (kind == 3) return mk_table(r);
  return mk_pair(r, r << 17);
}

static uint64_t fnv(uint64_t h, uint64_t v) { return (h ^ v) * 1099511628211ULL; }

int main(void) {
  const uint64_t steps = 10000000ULL * BENCH_SCALE;
  uint64_t x = 1;
  Clo q[16];
  for (uint64_t z = 0; z < 16; ++z) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    q[z] = make(z % 5, x >> 33);
  }

  uint64_t v = 0;
  for (uint64_t k = 0; k < steps; ++k) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    uint64_t r = x >> 33;
    if ((k & 255) == 255) {
      size_t slot = (r >> 8) & 15;
      Clo nc = make(((r >> 12) & 65535) % 5, r);
      q[slot].drop(q[slot].env);
      q[slot] = nc;
    }
    Clo f = q[r & 15];
    v = f.fn(f.env, v ^ r);
  }

  uint64_t h = 1469598103934665603ULL;
  h = fnv(h, v);
  for (int s = 0; s < 16; ++s) h = fnv(h, q[s].fn(q[s].env, 12345));
  h = fnv(h, x);
  for (int s = 0; s < 16; ++s) q[s].drop(q[s].env);
  printf("%lld\n", (long long)(h & 0x7fffffffffffffffULL));
  return 0;
}
