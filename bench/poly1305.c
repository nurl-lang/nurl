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
// formulation written out in C — radix 2^64, as OpenSSL's and BoringSSL's
// scalar code has it: the accumulator in two 64-bit words and a few bits
// above, the clamped key in two words with s1 = r1 + r1/4 carrying the
// 2^130 = 5 fold, each block four full 64x64->128 products (here
// `unsigned __int128`, in NURL `nurl_umulhi` / `nurl_mac_*`) and two small
// ones.
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

typedef unsigned __int128 u128;

static uint64_t le64(const uint8_t *p, uint64_t o) {
  uint64_t v = 0;
  for (uint64_t k = 0; k < 8; ++k) v = v | ((uint64_t)p[o + k] << (8 * k));
  return v;
}

// h = (h + m + pad * 2^128) * r, partially reduced mod 2^130 - 5 (h2 < 8)
static void poly_block(uint64_t *h, uint64_t t0, uint64_t t1, uint64_t pad, uint64_t r0, uint64_t r1,
                       uint64_t s1) {
  u128 a = (u128)h[0] + t0;
  uint64_t a0 = (uint64_t)a;
  a = (u128)h[1] + t1 + (uint64_t)(a >> 64);
  uint64_t a1 = (uint64_t)a;
  uint64_t a2 = h[2] + (uint64_t)(a >> 64) + pad;

  u128 d0 = (u128)a0 * r0 + (u128)a1 * s1;
  u128 d1 = (u128)a0 * r1 + (u128)a1 * r0 + a2 * s1;
  uint64_t d2 = a2 * r0;

  d1 = d1 + (uint64_t)(d0 >> 64);
  uint64_t g2 = d2 + (uint64_t)(d1 >> 64);
  uint64_t c = (g2 & ~3ULL) + (g2 >> 2);  // c * 2^130 = 5c
  u128 e = (u128)(uint64_t)d0 + c;
  h[0] = (uint64_t)e;
  e = (u128)(uint64_t)d1 + (uint64_t)(e >> 64);
  h[1] = (uint64_t)e;
  h[2] = (g2 & 3) + (uint64_t)(e >> 64);
}

// tag[0..15] = Poly1305(key[0..31], msg[0..len-1]).
static void poly1305_mac(uint8_t *tag, const uint8_t *key, const uint8_t *msg, uint64_t len) {
  uint64_t r0 = le64(key, 0) & 0x0ffffffc0fffffffULL;
  uint64_t r1 = le64(key, 8) & 0x0ffffffc0ffffffcULL;
  uint64_t s1 = r1 + (r1 >> 2);
  uint64_t h[3] = {0, 0, 0};

  uint64_t off = 0;
  uint64_t full = len & ~15ULL;
  while (off < full) {
    poly_block(h, le64(msg, off), le64(msg, off + 8), 1, r0, r1, s1);
    off = off + 16;
  }
  if (off < len) {
    // tail: the bytes, the 0x01 marker after them, zeros; no 2^128 bit
    uint64_t rem = len - off;
    uint64_t t0 = 0, t1 = 0;
    for (uint64_t j = 0; j <= rem; ++j) {
      uint64_t bv = 1;
      if (j < rem) bv = msg[off + j];
      if (j < 8) {
        t0 = t0 | (bv << (8 * j));
      } else {
        t1 = t1 | (bv << (8 * (j - 8)));
      }
    }
    poly_block(h, t0, t1, 0, r0, r1, s1);
  }

  // h + 5 reaches 2^130 exactly when h >= p; then its low 128 bits are h - p
  u128 g = (u128)h[0] + 5;
  uint64_t g0 = (uint64_t)g;
  g = (u128)h[1] + (uint64_t)(g >> 64);
  uint64_t g1 = (uint64_t)g;
  uint64_t g2 = h[2] + (uint64_t)(g >> 64);
  uint64_t mask = 0 - (g2 >> 2);
  uint64_t f0 = (h[0] & ~mask) | (g0 & mask);
  uint64_t f1 = (h[1] & ~mask) | (g1 & mask);

  // tag = (h + s) mod 2^128
  u128 w = (u128)f0 + le64(key, 16);
  f0 = (uint64_t)w;
  f1 = f1 + le64(key, 24) + (uint64_t)(w >> 64);
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
