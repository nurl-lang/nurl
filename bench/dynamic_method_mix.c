// benchmark-contract: dynamic-method-mix;objects=64;impls=4(adder,mixer,shifter,lookup16);kind=(r>>8)%4;steps=10000000;lcg=mmix(seed=1);draw=state>>33;obj=r&63;chain=v=apply(o,v^r)+weight(o);fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// dynamic_method_mix — 10M steps over 64 objects behind one two-method
// interface (see dynamic_method_mix.nu for the shape). C has no trait
// objects, so each object is what NURL's `%Op` and Rust's `Box<dyn Op>`
// lower to: a { data pointer, vtable pointer } pair, the data malloc'd
// per object and the vtable a static table of function pointers per
// type. The lookup type owns a separately malloc'd table, as a Vec
// field's buffer is separate from its struct.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

typedef struct {
  void (*drop)(void *self);
  uint64_t (*apply)(const void *self, uint64_t x);
  uint64_t (*weight)(const void *self);
} OpVT;

typedef struct { void *data; const OpVT *vt; } Op;

static void *xmalloc(size_t n) {
  void *p = malloc(n);
  if (!p) abort();
  return p;
}

static void drop_plain(void *self) { free(self); }

typedef struct { uint64_t c; } Adder;
static uint64_t adder_apply(const void *s, uint64_t x) { return x + ((const Adder *)s)->c; }
static uint64_t adder_weight(const void *s) { return ((const Adder *)s)->c & 7; }
static const OpVT ADDER_VT = { drop_plain, adder_apply, adder_weight };

typedef struct { uint64_t m, s; } Mixer;
static uint64_t mixer_apply(const void *s, uint64_t x) {
  const Mixer *o = s;
  return (x * o->m) ^ o->s;
}
static uint64_t mixer_weight(const void *s) { return ((const Mixer *)s)->s & 7; }
static const OpVT MIXER_VT = { drop_plain, mixer_apply, mixer_weight };

typedef struct { uint64_t a, b, c; } Shifter;
static uint64_t shifter_apply(const void *s, uint64_t x) {
  const Shifter *o = s;
  return ((x >> o->a) ^ (x << o->b)) + o->c;
}
static uint64_t shifter_weight(const void *s) { return ((const Shifter *)s)->a; }
static const OpVT SHIFTER_VT = { drop_plain, shifter_apply, shifter_weight };

typedef struct { uint64_t *t; size_t len; } Lookup;
static uint64_t lookup_at(const Lookup *o, size_t j) {
  if (j >= o->len) abort();
  return o->t[j];
}
static uint64_t lookup_apply(const void *s, uint64_t x) { return x ^ lookup_at(s, x & 15); }
static uint64_t lookup_weight(const void *s) { return lookup_at(s, 0) & 7; }
static void lookup_drop(void *s) {
  free(((Lookup *)s)->t);
  free(s);
}
static const OpVT LOOKUP_VT = { lookup_drop, lookup_apply, lookup_weight };

// An object of kind 0..3, its fields drawn from `r`.
static Op make(uint64_t kind, uint64_t r) {
  if (kind == 0) {
    Adder *o = xmalloc(sizeof *o);
    o->c = r;
    return (Op){ o, &ADDER_VT };
  }
  if (kind == 1) {
    Mixer *o = xmalloc(sizeof *o);
    o->m = r | 1; o->s = r >> 5;
    return (Op){ o, &MIXER_VT };
  }
  if (kind == 2) {
    Shifter *o = xmalloc(sizeof *o);
    o->a = (r & 31) + 1; o->b = ((r >> 5) & 31) + 1; o->c = r * 3;
    return (Op){ o, &SHIFTER_VT };
  }
  Lookup *o = xmalloc(sizeof *o);
  o->t = xmalloc(16 * sizeof(uint64_t));
  o->len = 16;
  for (uint64_t j = 0; j < 16; ++j) o->t[j] = (r ^ j) * 2654435761ULL + j;
  return (Op){ o, &LOOKUP_VT };
}

static uint64_t fnv(uint64_t h, uint64_t v) { return (h ^ v) * 1099511628211ULL; }

int main(void) {
  const uint64_t steps = 10000000ULL * BENCH_SCALE;
  uint64_t x = 1;
  Op objs[64];
  for (int z = 0; z < 64; ++z) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    uint64_t r = x >> 33;
    objs[z] = make((r >> 8) % 4, r);
  }

  uint64_t v = 0;
  for (uint64_t k = 0; k < steps; ++k) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    uint64_t r = x >> 33;
    Op o = objs[r & 63];
    v = o.vt->apply(o.data, v ^ r) + o.vt->weight(o.data);
  }

  uint64_t h = 1469598103934665603ULL;
  h = fnv(h, v);
  for (int s = 0; s < 64; ++s) {
    Op g = objs[s];
    h = fnv(h, g.vt->apply(g.data, 12345) + g.vt->weight(g.data));
  }
  h = fnv(h, x);
  for (int s = 0; s < 64; ++s) objs[s].vt->drop(objs[s].data);
  printf("%lld\n", (long long)(h & 0x7fffffffffffffffULL));
  return 0;
}
