// benchmark-contract: poly1305;rfc8439;message=16384;macs=4096;key=chained;checksum=tag-le64
//
// poly1305 — the RFC 8439 one-time authenticator. A 16 KiB message is
// MACed 4096 times (64 MiB); every tag is XORed back into both halves of
// the key, so each MAC depends on the one before and none can be hoisted.
// The multiply-and-carry chain through the accumulator is serial across
// a message's 1024 blocks: the integer multiplier's latency, not its
// throughput.
//
// The NURL column calls the standard library's `poly1305_mac`
// (stdlib/std/chacha20poly1305.nu). This file is that implementation's
// formulation written out in C — poly1305-donna-64: the accumulator and
// the clamped key in three limbs at radix 2^44 (44/44/42 bits), each
// block nine full 64x64->128 products (here `unsigned __int128`, in NURL
// `nurl_umulhi`) and a carry chain with the 2^130 = 5 fold.
//
// Contract: the process prints exactly one line — the final tag's first
// eight bytes as a little-endian integer, masked to 63 bits — and nothing
// else. `bench/bench.sh` gates on the NURL, C and Rust implementations
// printing the same line before it reports a timing.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

#define M44 0xfffffffffffULL
#define M42 0x3ffffffffffULL

typedef unsigned __int128 u128;

static uint64_t le64(const uint8_t *p, uint64_t o) {
  uint64_t v = 0;
  for (uint64_t k = 0; k < 8; ++k) v = v | ((uint64_t)p[o + k] << (8 * k));
  return v;
}

// tag[0..15] = Poly1305(key[0..31], msg[0..len-1]).
static void poly1305_mac(uint8_t *tag, const uint8_t *key, const uint8_t *msg, uint64_t len) {
  uint64_t kt0 = le64(key, 0);
  uint64_t kt1 = le64(key, 8);
  uint64_t r0 = kt0 & 0xffc0fffffffULL;
  uint64_t r1 = ((kt0 >> 44) | (kt1 << 20)) & 0xfffffc0ffffULL;
  uint64_t r2 = (kt1 >> 24) & 0x00ffffffc0fULL;
  uint64_t s1 = r1 * 20;
  uint64_t s2 = r2 * 20;
  uint64_t h0 = 0, h1 = 0, h2 = 0;

  uint64_t off = 0;
  while (off < len) {
    uint64_t rem = len - off;
    uint64_t t0 = 0, t1 = 0;
    uint64_t hibit = 1ULL << 40;
    if (rem >= 16) {
      t0 = le64(msg, off);
      t1 = le64(msg, off + 8);
    } else {
      // tail: the bytes, the 0x01 marker after them, zeros; no hibit
      for (uint64_t j = 0; j <= rem; ++j) {
        uint64_t bv = 1;
        if (j < rem) bv = msg[off + j];
        if (j < 8) {
          t0 = t0 | (bv << (8 * j));
        } else {
          t1 = t1 | (bv << (8 * (j - 8)));
        }
      }
      hibit = 0;
    }
    h0 = h0 + (t0 & M44);
    h1 = h1 + (((t0 >> 44) | (t1 << 20)) & M44);
    h2 = h2 + ((t1 >> 24) & M42) + hibit;

    u128 d0 = (u128)h0 * r0 + (u128)h1 * s2 + (u128)h2 * s1;
    u128 d1 = (u128)h0 * r1 + (u128)h1 * r0 + (u128)h2 * s2;
    u128 d2 = (u128)h0 * r2 + (u128)h1 * r1 + (u128)h2 * r0;

    uint64_t c = (uint64_t)(d0 >> 44);
    h0 = (uint64_t)d0 & M44;
    d1 = d1 + c;
    c = (uint64_t)(d1 >> 44);
    h1 = (uint64_t)d1 & M44;
    d2 = d2 + c;
    c = (uint64_t)(d2 >> 42);
    h2 = (uint64_t)d2 & M42;
    h0 = h0 + c * 5;
    c = h0 >> 44;
    h0 = h0 & M44;
    h1 = h1 + c;

    off = off + 16;
  }

  // fully carry h
  uint64_t c = h1 >> 44;
  h1 = h1 & M44;
  h2 = h2 + c;
  c = h2 >> 42;
  h2 = h2 & M42;
  h0 = h0 + c * 5;
  c = h0 >> 44;
  h0 = h0 & M44;
  h1 = h1 + c;

  // g = h + 5 - 2^130; keep h if g borrowed (h < p), else take g
  uint64_t g0 = h0 + 5;
  c = g0 >> 44;
  g0 = g0 & M44;
  uint64_t g1 = h1 + c;
  c = g1 >> 44;
  g1 = g1 & M44;
  uint64_t g2 = h2 + c - (1ULL << 42);
  uint64_t mask = (g2 >> 63) - 1;
  g0 = g0 & mask;
  g1 = g1 & mask;
  g2 = g2 & mask;
  uint64_t imask = ~mask;
  h0 = (h0 & imask) | g0;
  h1 = (h1 & imask) | g1;
  h2 = (h2 & imask) | g2;

  // tag = (h + s) mod 2^128
  uint64_t st0 = le64(key, 16);
  uint64_t st1 = le64(key, 24);
  uint64_t f0 = h0 | (h1 << 44);
  uint64_t f1 = (h1 >> 20) | (h2 << 24);
  f0 = f0 + st0;
  f1 = f1 + st1 + (f0 < st0 ? 1 : 0);
  for (uint64_t k = 0; k < 8; ++k) {
    tag[k] = (uint8_t)((f0 >> (8 * k)) & 255);
    tag[k + 8] = (uint8_t)((f1 >> (8 * k)) & 255);
  }
}

int main(void) {
  const uint64_t macs = 4096ULL * BENCH_SCALE;
  const uint64_t len = 16384;
  uint8_t tag[16];
  uint8_t key[32];
  for (uint64_t i = 0; i < 32; ++i) key[i] = (uint8_t)((i * 7 + 3) & 255);
  uint8_t *msg = (uint8_t *)malloc(len);
  for (uint64_t i = 0; i < len; ++i) msg[i] = (uint8_t)((i * 31 + 17) & 255);

  for (uint64_t k = 0; k < macs; ++k) {
    poly1305_mac(tag, key, msg, len);
    for (uint64_t i = 0; i < 16; ++i) {
      key[i] = key[i] ^ tag[i];
      key[i + 16] = key[i + 16] ^ tag[i];
    }
  }

  uint64_t v = le64(tag, 0);
  free(msg);
  printf("%llu\n", (unsigned long long)(v & 0x7fffffffffffffffULL));
  return 0;
}
