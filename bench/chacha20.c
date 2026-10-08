// benchmark-contract: chacha20;rfc8439;key=00..1f;nonce=000000090000004a00000000;counter=1;buffer=16384;passes=1024;checksum=fnv1a64-words
//
// chacha20 — the RFC 8439 stream cipher, scalar. A 16 KiB buffer is
// encrypted in place 1024 times (16 MiB of keystream), the block counter
// running on across passes so no two blocks repeat. Each 64-byte block
// is 20 rounds of 32-bit add/rotate/xor over a 16-word state — a pure ALU
// mill with four independent quarter-round chains per half-round — and
// the keystream is XORed into the buffer byte by byte.
//
// The key, nonce and counter are RFC 8439 §2.3.2's block-function test
// vector, so the first keystream block is the one the RFC prints.
//
// The NURL column calls the standard library's `chacha20_xor`
// (stdlib/std/chacha20poly1305.nu) — whose block function is written
// over `v128` lanes, four quarter-rounds a vector instruction, on every
// little-endian target. This file is the portable scalar RFC formulation,
// the one the stdlib keeps as its big-endian fallback: C and Rust carry
// no ChaCha20 of their own, and neither compiler turns the scalar rounds
// into the lane form. That difference is what this row measures.
//
// Contract: the process prints exactly one line — an FNV-style fold of the
// final buffer's 64-bit little-endian words, masked to 63 bits — and
// nothing else. `bench/bench.sh` gates on the NURL, C and Rust
// implementations printing the same line before it reports a timing.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

static uint32_t rotl32(uint32_t x, uint32_t n) { return (x << n) | (x >> (32 - n)); }

static void quarter(uint32_t *x, int a, int b, int c, int d) {
  x[a] = x[a] + x[b];
  x[d] = rotl32(x[d] ^ x[a], 16);
  x[c] = x[c] + x[d];
  x[b] = rotl32(x[b] ^ x[c], 12);
  x[a] = x[a] + x[b];
  x[d] = rotl32(x[d] ^ x[a], 8);
  x[c] = x[c] + x[d];
  x[b] = rotl32(x[b] ^ x[c], 7);
}

// One 64-byte keystream block from the input state `in`, XORed into
// buf[off .. off+63]. `x` is the caller's 16-word working state.
static void chacha20_block_xor(const uint32_t *in, uint32_t *x, uint8_t *buf, uint64_t off) {
  for (int i = 0; i < 16; ++i) x[i] = in[i];
  for (int r = 0; r < 10; ++r) {
    quarter(x, 0, 4, 8, 12);
    quarter(x, 1, 5, 9, 13);
    quarter(x, 2, 6, 10, 14);
    quarter(x, 3, 7, 11, 15);
    quarter(x, 0, 5, 10, 15);
    quarter(x, 1, 6, 11, 12);
    quarter(x, 2, 7, 8, 13);
    quarter(x, 3, 4, 9, 14);
  }
  for (int i = 0; i < 16; ++i) {
    uint32_t w = x[i] + in[i];
    uint64_t p = off + 4 * (uint64_t)i;
    buf[p] = buf[p] ^ (uint8_t)(w & 255);
    buf[p + 1] = buf[p + 1] ^ (uint8_t)((w >> 8) & 255);
    buf[p + 2] = buf[p + 2] ^ (uint8_t)((w >> 16) & 255);
    buf[p + 3] = buf[p + 3] ^ (uint8_t)((w >> 24) & 255);
  }
}

static uint32_t le32(const uint8_t *p, uint64_t o) {
  return (uint32_t)p[o] | ((uint32_t)p[o + 1] << 8) | ((uint32_t)p[o + 2] << 16) |
         ((uint32_t)p[o + 3] << 24);
}

static uint64_t le64(const uint8_t *p, uint64_t o) {
  uint64_t v = 0;
  for (uint64_t k = 0; k < 8; ++k) v = v | ((uint64_t)p[o + k] << (8 * k));
  return v;
}

// XOR the ChaCha20 keystream for (key, counter, nonce) into buf[0..len-1].
// `in` and `x` (16 words) and `ks` (64 bytes) are the caller's scratch.
static void chacha20_xor(uint8_t *buf, uint64_t len, const uint8_t *key, uint32_t counter,
                         const uint8_t *nonce, uint32_t *in, uint32_t *x, uint8_t *ks) {
  in[0] = 0x61707865;
  in[1] = 0x3320646e;
  in[2] = 0x79622d32;
  in[3] = 0x6b206574;
  for (uint64_t i = 0; i < 8; ++i) in[4 + i] = le32(key, 4 * i);
  in[12] = counter;
  in[13] = le32(nonce, 0);
  in[14] = le32(nonce, 4);
  in[15] = le32(nonce, 8);
  uint64_t off = 0;
  while (off + 64 <= len) {
    chacha20_block_xor(in, x, buf, off);
    in[12] = in[12] + 1;
    off = off + 64;
  }
  if (off < len) {
    // a final partial block: keystream into ks, then byte by byte
    for (uint64_t i = 0; i < 64; ++i) ks[i] = 0;
    chacha20_block_xor(in, x, ks, 0);
    for (uint64_t i = 0; off + i < len; ++i) buf[off + i] = buf[off + i] ^ ks[i];
  }
}

int main(void) {
  const uint64_t passes = 1024ULL * BENCH_SCALE;
  const uint64_t len = 16384;
  uint32_t in[16];
  uint32_t x[16];
  uint8_t ks[64];
  uint8_t key[32];
  uint8_t nonce[12];
  for (uint64_t i = 0; i < 32; ++i) key[i] = (uint8_t)i;
  for (uint64_t i = 0; i < 12; ++i) nonce[i] = 0;
  nonce[3] = 0x09;
  nonce[7] = 0x4a;

  uint8_t *buf = (uint8_t *)malloc(len);
  for (uint64_t i = 0; i < len; ++i) buf[i] = (uint8_t)(i & 255);

  // the block counter runs on across passes: pass p starts at 1 + p*256
  for (uint64_t pass = 0; pass < passes; ++pass)
    chacha20_xor(buf, len, key, (uint32_t)(1 + pass * (len / 64)), nonce, in, x, ks);

  uint64_t h = 0xcbf29ce484222325ULL;
  for (uint64_t i = 0; i < len; i += 8) h = (h ^ le64(buf, i)) * 0x100000001b3ULL;
  free(buf);
  printf("%llu\n", (unsigned long long)(h & 0x7fffffffffffffffULL));
  return 0;
}
