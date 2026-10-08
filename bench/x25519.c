// benchmark-contract: x25519;rfc7748;k=u=9;iterations=1000;checksum=k-le64
//
// x25519 — RFC 7748 X25519 Diffie-Hellman, variable base: the Montgomery
// ladder every ECDH key exchange runs. The workload is RFC 7748 §5.2's
// iteration test — k = u = 9, then 1000 times (k, u) <- (X25519(k, u), k)
// — so each scalar multiplication consumes the previous result and the
// whole run is one serial chain. At x1 the final k is the RFC's own
// 1000-iteration value, 684cf59ba8330955…, so the printed line is
// 0x550933a89bf54c68 = 6127485567278337128, read from the RFC.
//
// The NURL column calls the standard library's `x25519`
// (stdlib/std/x25519.nu). This file is that implementation's formulation
// written out in C: the TweetNaCl ladder (255 steps, five multiplies,
// four squarings and one multiply by 121665 each) over the
// curve25519-donna-c64 field — five unsigned limbs at radix 2^51, every
// limb product a full 64x64->128 multiply (here `unsigned __int128`, in
// NURL `nurl_umulhi` / `nurl_mac_*`) — and the ref10 inversion chain
// (254 squarings, 11 multiplies). Same algorithm, same operation count.
//
// Contract: the process prints exactly one line — the final k's first
// eight bytes as a little-endian integer, masked to 63 bits — and nothing
// else. `bench/bench.sh` gates on the NURL, C and Rust implementations
// printing the same line before it reports a timing.
#include <stdint.h>
#include <stdio.h>

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

// Every field element lives in one flat limb array `g`, addressed by its
// offset: the ladder's operations alias freely (`fmul(g, FA, FA, FC)`
// multiplies in place), and an offset into one array is the one way to
// spell that the same in C and Rust.
#define FA 0
#define FB 5
#define FC 10
#define FD 15
#define FE 20
#define FF 25
#define FX 30
#define FK 35    // the constant 121665
#define FZ2 40   // inversion scratch, five elements
#define FZ9 45
#define FZ11 50
#define FZ5 55
#define FZ10 60
#define FZ50 65
#define FT 70
#define GLIMBS 75

#define M51 0x7ffffffffffffULL

typedef unsigned __int128 u128;

// Constant-time swap of elements p and q when b == 1.
static void sel25519(uint64_t *g, uint64_t p, uint64_t q, uint64_t b) {
  uint64_t c = 0 - b;
  for (uint64_t i = 0; i < 5; ++i) {
    uint64_t t = c & (g[p + i] ^ g[q + i]);
    g[p + i] = g[p + i] ^ t;
    g[q + i] = g[q + i] ^ t;
  }
}

// o = a + b, limbwise; the next multiply carries.
static void fadd(uint64_t *g, uint64_t o, uint64_t a, uint64_t b) {
  for (uint64_t i = 0; i < 5; ++i) g[o + i] = g[a + i] + g[b + i];
}

// o = a - b + 2p, limbwise, so no limb goes negative.
static void fsub(uint64_t *g, uint64_t o, uint64_t a, uint64_t b) {
  g[o] = g[a] + 0xfffffffffffdaULL - g[b];
  g[o + 1] = g[a + 1] + 0xffffffffffffeULL - g[b + 1];
  g[o + 2] = g[a + 2] + 0xffffffffffffeULL - g[b + 2];
  g[o + 3] = g[a + 3] + 0xffffffffffffeULL - g[b + 3];
  g[o + 4] = g[a + 4] + 0xffffffffffffeULL - g[b + 4];
}

// Five 128-bit column sums -> five 51-bit limbs at o, folding the top x19.
static void carry_out(uint64_t *g, uint64_t o, u128 t0, u128 t1, u128 t2, u128 t3, u128 t4) {
  uint64_t g0 = (uint64_t)t0 & M51;
  t1 = t1 + (uint64_t)(t0 >> 51);
  uint64_t g1 = (uint64_t)t1 & M51;
  t2 = t2 + (uint64_t)(t1 >> 51);
  uint64_t g2 = (uint64_t)t2 & M51;
  t3 = t3 + (uint64_t)(t2 >> 51);
  uint64_t g3 = (uint64_t)t3 & M51;
  t4 = t4 + (uint64_t)(t3 >> 51);
  uint64_t g4 = (uint64_t)t4 & M51;
  uint64_t c = (uint64_t)(t4 >> 51);
  g0 = g0 + c * 19;
  c = g0 >> 51;
  g0 = g0 & M51;
  g1 = g1 + c;
  c = g1 >> 51;
  g1 = g1 & M51;
  g2 = g2 + c;
  g[o] = g0;
  g[o + 1] = g1;
  g[o + 2] = g2;
  g[o + 3] = g3;
  g[o + 4] = g4;
}

// o = a * b mod p (donna-c64 fmul). o may alias a or b.
static void fmul(uint64_t *g, uint64_t o, uint64_t a, uint64_t b) {
  uint64_t r0 = g[a], r1 = g[a + 1], r2 = g[a + 2], r3 = g[a + 3], r4 = g[a + 4];
  uint64_t s0 = g[b], s1 = g[b + 1], s2 = g[b + 2], s3 = g[b + 3], s4 = g[b + 4];
  uint64_t f1 = r1 * 19, f2 = r2 * 19, f3 = r3 * 19, f4 = r4 * 19;
  u128 t0 = (u128)r0 * s0 + (u128)f4 * s1 + (u128)f1 * s4 + (u128)f2 * s3 + (u128)f3 * s2;
  u128 t1 = (u128)r0 * s1 + (u128)r1 * s0 + (u128)f4 * s2 + (u128)f2 * s4 + (u128)f3 * s3;
  u128 t2 = (u128)r0 * s2 + (u128)r1 * s1 + (u128)r2 * s0 + (u128)f4 * s3 + (u128)f3 * s4;
  u128 t3 = (u128)r0 * s3 + (u128)r1 * s2 + (u128)r2 * s1 + (u128)r3 * s0 + (u128)f4 * s4;
  u128 t4 = (u128)r0 * s4 + (u128)r1 * s3 + (u128)r2 * s2 + (u128)r3 * s1 + (u128)r4 * s0;
  carry_out(g, o, t0, t1, t2, t3, t4);
}

// o = a^2 mod p (donna-c64 fsquare: the cross terms doubled once).
static void fsq(uint64_t *g, uint64_t o, uint64_t a) {
  uint64_t r0 = g[a], r1 = g[a + 1], r2 = g[a + 2], r3 = g[a + 3], r4 = g[a + 4];
  uint64_t d0 = r0 * 2, d1 = r1 * 2, d2 = r2 * 38, d419 = r4 * 19, d4 = d419 * 2;
  uint64_t r319 = r3 * 19;
  u128 t0 = (u128)r0 * r0 + (u128)d4 * r1 + (u128)d2 * r3;
  u128 t1 = (u128)d0 * r1 + (u128)d4 * r2 + (u128)r3 * r319;
  u128 t2 = (u128)d0 * r2 + (u128)r1 * r1 + (u128)d4 * r3;
  u128 t3 = (u128)d0 * r3 + (u128)d1 * r2 + (u128)r4 * d419;
  u128 t4 = (u128)d0 * r4 + (u128)d1 * r3 + (u128)r2 * r2;
  carry_out(g, o, t0, t1, t2, t3, t4);
}

static void fcopy(uint64_t *g, uint64_t o, uint64_t a) {
  for (uint64_t i = 0; i < 5; ++i) g[o + i] = g[a + i];
}

// o = o^(2^n): n back-to-back squarings.
static void fsqn(uint64_t *g, uint64_t o, uint64_t n) {
  for (uint64_t k = 0; k < n; ++k) fsq(g, o, o);
}

// io = io^(p-2) = 1/io: the ref10 addition chain.
static void inv25519(uint64_t *g, uint64_t io) {
  fsq(g, FZ2, io);
  fsq(g, FZ9, FZ2);
  fsq(g, FZ9, FZ9);
  fmul(g, FZ9, FZ9, io);
  fmul(g, FZ11, FZ9, FZ2);
  fsq(g, FZ5, FZ11);
  fmul(g, FZ5, FZ5, FZ9);
  fcopy(g, FZ10, FZ5);
  fsqn(g, FZ10, 5);
  fmul(g, FZ10, FZ10, FZ5);
  fcopy(g, FT, FZ10);
  fsqn(g, FT, 10);
  fmul(g, FT, FT, FZ10);
  fcopy(g, FZ50, FT);
  fsqn(g, FZ50, 20);
  fmul(g, FZ50, FZ50, FT);
  fsqn(g, FZ50, 10);
  fmul(g, FZ50, FZ50, FZ10);
  fcopy(g, FT, FZ50);
  fsqn(g, FT, 50);
  fmul(g, FT, FT, FZ50);
  fcopy(g, FZ10, FT);
  fsqn(g, FZ10, 100);
  fmul(g, FZ10, FZ10, FT);
  fsqn(g, FZ10, 50);
  fmul(g, FZ10, FZ10, FZ50);
  fsqn(g, FZ10, 5);
  fmul(g, FZ10, FZ10, FZ11);
  fcopy(g, io, FZ10);
}

static uint64_t le64(const uint8_t *p, uint64_t o) {
  uint64_t v = 0;
  for (uint64_t k = 0; k < 8; ++k) v = v | ((uint64_t)p[o + k] << (8 * k));
  return v;
}

// 32 little-endian bytes -> element o, the top bit dropped (fexpand).
static void unpack25519(uint64_t *g, uint64_t o, const uint8_t *n) {
  g[o] = le64(n, 0) & M51;
  g[o + 1] = (le64(n, 6) >> 3) & M51;
  g[o + 2] = (le64(n, 12) >> 6) & M51;
  g[o + 3] = (le64(n, 19) >> 1) & M51;
  g[o + 4] = (le64(n, 24) >> 12) & M51;
}

// Element n fully reduced mod p -> 32 little-endian bytes (fcontract).
static void pack25519(uint8_t *out, const uint64_t *g, uint64_t n) {
  uint64_t h0 = g[n], h1 = g[n + 1], h2 = g[n + 2], h3 = g[n + 3], h4 = g[n + 4];
  for (uint64_t pass = 0; pass < 2; ++pass) {
    h1 = h1 + (h0 >> 51);
    h0 = h0 & M51;
    h2 = h2 + (h1 >> 51);
    h1 = h1 & M51;
    h3 = h3 + (h2 >> 51);
    h2 = h2 & M51;
    h4 = h4 + (h3 >> 51);
    h3 = h3 & M51;
    h0 = h0 + 19 * (h4 >> 51);
    h4 = h4 & M51;
  }
  h0 = h0 + 19;
  h1 = h1 + (h0 >> 51);
  h0 = h0 & M51;
  h2 = h2 + (h1 >> 51);
  h1 = h1 & M51;
  h3 = h3 + (h2 >> 51);
  h2 = h2 & M51;
  h4 = h4 + (h3 >> 51);
  h3 = h3 & M51;
  h0 = h0 + 19 * (h4 >> 51);
  h4 = h4 & M51;
  h0 = h0 + 0x7ffffffffffedULL;
  h1 = h1 + M51;
  h2 = h2 + M51;
  h3 = h3 + M51;
  h4 = h4 + M51;
  h1 = h1 + (h0 >> 51);
  h0 = h0 & M51;
  h2 = h2 + (h1 >> 51);
  h1 = h1 & M51;
  h3 = h3 + (h2 >> 51);
  h2 = h2 & M51;
  h4 = h4 + (h3 >> 51);
  h3 = h3 & M51;
  h4 = h4 & M51;
  uint64_t w0 = h0 | (h1 << 51);
  uint64_t w1 = (h1 >> 13) | (h2 << 38);
  uint64_t w2 = (h2 >> 26) | (h3 << 25);
  uint64_t w3 = (h3 >> 39) | (h4 << 12);
  for (uint64_t k = 0; k < 8; ++k) {
    out[k] = (uint8_t)((w0 >> (8 * k)) & 255);
    out[k + 8] = (uint8_t)((w1 >> (8 * k)) & 255);
    out[k + 16] = (uint8_t)((w2 >> (8 * k)) & 255);
    out[k + 24] = (uint8_t)((w3 >> (8 * k)) & 255);
  }
}

// q = X25519(n, p): scalar n (clamped into z), u-coordinate p. `g` and
// `z` (32 bytes) are the caller's scratch.
static void x25519(uint8_t *q, const uint8_t *n, const uint8_t *p, uint64_t *g, uint8_t *z) {
  for (uint64_t i = 0; i < 32; ++i) z[i] = n[i];
  z[31] = (uint8_t)((n[31] & 127) | 64);
  z[0] = (uint8_t)(n[0] & 248);
  unpack25519(g, FX, p);
  for (uint64_t i = 0; i < 5; ++i) {
    g[FA + i] = 0;
    g[FB + i] = g[FX + i];
    g[FC + i] = 0;
    g[FD + i] = 0;
  }
  g[FA] = 1;
  g[FD] = 1;
  for (int64_t i = 254; i >= 0; --i) {
    uint64_t r = ((uint64_t)z[i >> 3] >> (i & 7)) & 1;
    sel25519(g, FA, FB, r);
    sel25519(g, FC, FD, r);
    fadd(g, FE, FA, FC);
    fsub(g, FA, FA, FC);
    fadd(g, FC, FB, FD);
    fsub(g, FB, FB, FD);
    fsq(g, FD, FE);
    fsq(g, FF, FA);
    fmul(g, FA, FC, FA);
    fmul(g, FC, FB, FE);
    fadd(g, FE, FA, FC);
    fsub(g, FA, FA, FC);
    fsq(g, FB, FA);
    fsub(g, FC, FD, FF);
    fmul(g, FA, FC, FK);
    fadd(g, FA, FA, FD);
    fmul(g, FC, FC, FA);
    fmul(g, FA, FD, FF);
    fmul(g, FD, FB, FX);
    fsq(g, FB, FE);
    sel25519(g, FA, FB, r);
    sel25519(g, FC, FD, r);
  }
  inv25519(g, FC);
  fmul(g, FA, FA, FC);
  pack25519(q, g, FA);
}

int main(void) {
  const uint64_t iterations = 1000ULL * BENCH_SCALE;
  uint64_t g[GLIMBS];
  uint8_t z[32], k[32], u[32], r[32];
  for (uint64_t i = 0; i < GLIMBS; ++i) g[i] = 0;
  g[FK] = 121665;
  for (uint64_t i = 0; i < 32; ++i) {
    k[i] = 0;
    u[i] = 0;
  }
  k[0] = 9;
  u[0] = 9;

  for (uint64_t it = 0; it < iterations; ++it) {
    x25519(r, k, u, g, z);
    for (uint64_t i = 0; i < 32; ++i) {
      u[i] = k[i];
      k[i] = r[i];
    }
  }

  uint64_t v = le64(k, 0);
  printf("%llu\n", (unsigned long long)(v & 0x7fffffffffffffffULL));
  return 0;
}
