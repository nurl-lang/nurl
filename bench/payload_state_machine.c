// benchmark-contract: payload-state-machine;events=10000000;lcg=mmix(seed=1);draw=state>>29;sel=r&7(0-2:Add,3:Scale,4:Push,5:Pop,6-7:Probe);max_depth=16;fault=DepthLow(String)|DepthHigh(u64,String);fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// payload_state_machine — 10M events through a state machine whose step
// returns either the next state or a fault carrying an owned message
// (see payload_state_machine.nu for the shape). C has no sum types, so
// the enum, the option and the result are tagged structs, `step` returns
// the result struct by value, and a fault's message is a malloc'd buffer
// the handler reads and frees — the same allocation the NURL String and
// the Rust String make.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

typedef struct { uint64_t acc, depth, steps; } St;

enum { EV_ADD, EV_SCALE, EV_PUSH, EV_POP, EV_PROBE };
typedef struct { int tag; uint64_t a, b; } Ev;

typedef struct { int some; uint64_t v; } OptU64;

enum { F_DEPTH_LOW, F_DEPTH_HIGH };
typedef struct { int tag; uint64_t d; char *msg; size_t len; } Fault;

typedef struct { int ok; St st; Fault f; } Res;

static Ev decode(uint64_t r) {
  uint64_t sel = r & 7, rest = r >> 3;
  Ev e = { EV_PROBE, rest, 0 };
  if (sel < 3) { e.tag = EV_ADD; e.a = rest & 65535; }
  else if (sel == 3) { e.tag = EV_SCALE; e.a = (rest & 7) + 1; e.b = (rest >> 3) & 255; }
  else if (sel == 4) { e.tag = EV_PUSH; }
  else if (sel == 5) { e.tag = EV_POP; }
  return e;
}

static OptU64 lookup(uint64_t key) {
  OptU64 o = { 0, 0 };
  if ((key & 3) == 0) return o;
  o.some = 1; o.v = key * 31;
  return o;
}

// The fault's message: a fixed text and one byte chosen by the state.
static Fault fault_text(int tag, uint64_t d, const char *base, uint64_t acc, uint64_t c0) {
  size_t n = strlen(base);
  char *m = malloc(n + 2);
  if (!m) abort();
  memcpy(m, base, n);
  m[n] = (char)(c0 + (acc & 15));
  m[n + 1] = 0;
  Fault f = { tag, d, m, n + 1 };
  return f;
}

static Res ok(St s) { Res r; r.ok = 1; r.st = s; r.f.msg = NULL; return r; }
static Res err(Fault f) { Res r; r.ok = 0; r.st.acc = r.st.depth = r.st.steps = 0; r.f = f; return r; }

static Res step(St s, Ev e) {
  switch (e.tag) {
  case EV_ADD: return ok((St){ s.acc + e.a, s.depth, s.steps + 1 });
  case EV_SCALE: return ok((St){ s.acc * e.a + e.b, s.depth, s.steps + 1 });
  case EV_PUSH:
    if (s.depth >= 16) return err(fault_text(F_DEPTH_HIGH, s.depth, "stack overflow at ", s.acc, 65));
    return ok((St){ s.acc, s.depth + 1, s.steps + 1 });
  case EV_POP:
    if (s.depth == 0) return err(fault_text(F_DEPTH_LOW, 0, "stack underflow at ", s.acc, 97));
    return ok((St){ s.acc ^ s.depth, s.depth - 1, s.steps + 1 });
  default: {
    OptU64 o = lookup(e.a);
    if (o.some) return ok((St){ s.acc ^ o.v, s.depth, s.steps + 1 });
    return ok((St){ s.acc + 1, s.depth, s.steps + 1 });
  }
  }
}

static uint64_t fnv(uint64_t h, uint64_t v) { return (h ^ v) * 1099511628211ULL; }

// What a handler takes from a fault's message: its length and last byte.
static uint64_t text_sum(const Fault *f) {
  return (uint64_t)f->len + (uint64_t)(unsigned char)f->msg[f->len - 1];
}

int main(void) {
  const uint64_t events = 10000000ULL * BENCH_SCALE;
  St st = { 1, 0, 0 };
  uint64_t x = 1, errh = 1469598103934665603ULL, faults = 0;
  for (uint64_t k = 0; k < events; ++k) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    Ev ev = decode(x >> 29);
    Res res = step(st, ev);
    if (res.ok) {
      st = res.st;
    } else {
      if (res.f.tag == F_DEPTH_LOW) errh = fnv(errh, text_sum(&res.f));
      else errh = fnv(errh, res.f.d + text_sum(&res.f));
      free(res.f.msg);
      faults += 1;
      St n = { (st.acc >> 7) | (st.acc << 57), 0, st.steps };
      st = n;
    }
  }
  uint64_t h = 1469598103934665603ULL;
  h = fnv(h, st.acc);
  h = fnv(h, st.depth);
  h = fnv(h, st.steps);
  h = fnv(h, errh);
  h = fnv(h, faults);
  printf("%lld\n", (long long)(h & 0x7fffffffffffffffULL));
  return 0;
}
