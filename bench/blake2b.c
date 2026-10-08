// benchmark-contract: blake2b;rfc7693;outlen=64;unkeyed;message=16384;hashes=2048;chain=digest[0..8]->message[0..8];checksum=digest-le64
//
// blake2b — RFC 7693 BLAKE2b-512, unkeyed, scalar. A 16 KiB message is
// hashed 2048 times (32 MiB); before each hash the previous digest's first
// eight bytes overwrite the message's first eight, so every hash depends
// on the last and none can be hoisted. Each 128-byte block is 12 rounds of
// eight G mixes — 64-bit add/xor/rotate with message words picked through
// the SIGMA permutation table, a data-independent gather every round.
//
// Contract: the process prints exactly one line — the final digest's
// first eight bytes as a little-endian integer, masked to 63 bits — and
// nothing else. `bench/bench.sh` gates on the NURL, C and Rust
// implementations printing the same line before it reports a timing.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

static const uint64_t IV[8] = {0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL,
                               0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
                               0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL,
                               0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL};

static const uint8_t SIGMA[192] = {
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    14, 10, 4,  8,  9,  15, 13, 6,  1,  12, 0,  2,  11, 7,  5,  3,
    11, 8,  12, 0,  5,  2,  15, 13, 10, 14, 3,  6,  7,  1,  9,  4,
    7,  9,  3,  1,  13, 12, 11, 14, 2,  6,  5,  10, 4,  0,  15, 8,
    9,  0,  5,  7,  2,  4,  10, 15, 14, 1,  11, 12, 6,  8,  3,  13,
    2,  12, 6,  10, 0,  11, 8,  3,  4,  13, 7,  5,  15, 14, 1,  9,
    12, 5,  1,  15, 14, 13, 4,  10, 0,  7,  6,  3,  9,  2,  8,  11,
    13, 11, 7,  14, 12, 1,  3,  9,  5,  0,  15, 4,  8,  6,  2,  10,
    6,  15, 14, 9,  11, 3,  0,  8,  12, 2,  13, 7,  1,  4,  10, 5,
    10, 2,  8,  4,  7,  6,  1,  5,  15, 11, 9,  14, 3,  12, 13, 0,
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    14, 10, 4,  8,  9,  15, 13, 6,  1,  12, 0,  2,  11, 7,  5,  3};

static uint64_t rotr64(uint64_t x, uint64_t n) { return (x >> n) | (x << (64 - n)); }

static uint64_t le64(const uint8_t *p, uint64_t o) {
  uint64_t v = 0;
  for (int k = 7; k >= 0; --k) v = (v << 8) | (uint64_t)p[o + (uint64_t)k];
  return v;
}

static void mix(uint64_t *v, int a, int b, int c, int d, uint64_t x, uint64_t y) {
  v[a] = v[a] + v[b] + x;
  v[d] = rotr64(v[d] ^ v[a], 32);
  v[c] = v[c] + v[d];
  v[b] = rotr64(v[b] ^ v[c], 24);
  v[a] = v[a] + v[b] + y;
  v[d] = rotr64(v[d] ^ v[a], 16);
  v[c] = v[c] + v[d];
  v[b] = rotr64(v[b] ^ v[c], 63);
}

// Compress the 128-byte block at blk[o..o+127] into h[0..7]. `t` is the
// byte count so far (the high counter word is always 0 here), `last` is 1
// for the final block. `v` (16 words) and `m` (16 words) are scratch.
static void blake2b_compress(uint64_t *h, uint64_t *v, uint64_t *m, const uint8_t *blk,
                             uint64_t o, uint64_t t, uint64_t last) {
  for (uint64_t i = 0; i < 16; ++i) m[i] = le64(blk, o + 8 * i);
  for (uint64_t i = 0; i < 8; ++i) {
    v[i] = h[i];
    v[i + 8] = IV[i];
  }
  v[12] = v[12] ^ t;
  if (last == 1) v[14] = ~v[14];
  for (uint64_t r = 0; r < 12; ++r) {
    const uint8_t *s = SIGMA + 16 * r;
    mix(v, 0, 4, 8, 12, m[s[0]], m[s[1]]);
    mix(v, 1, 5, 9, 13, m[s[2]], m[s[3]]);
    mix(v, 2, 6, 10, 14, m[s[4]], m[s[5]]);
    mix(v, 3, 7, 11, 15, m[s[6]], m[s[7]]);
    mix(v, 0, 5, 10, 15, m[s[8]], m[s[9]]);
    mix(v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
    mix(v, 2, 7, 8, 13, m[s[12]], m[s[13]]);
    mix(v, 3, 4, 9, 14, m[s[14]], m[s[15]]);
  }
  for (uint64_t i = 0; i < 8; ++i) h[i] = h[i] ^ v[i] ^ v[i + 8];
}

// out[0..63] = BLAKE2b-512(msg[0..len-1]). `h` (8 words), `v` and `m`
// (16 words each) and `pad` (128 bytes, the zero-padded last block) are
// scratch.
static void blake2b(uint8_t *out, const uint8_t *msg, uint64_t len, uint64_t *h, uint64_t *v,
                    uint64_t *m, uint8_t *pad) {
  for (uint64_t i = 0; i < 8; ++i) h[i] = IV[i];
  h[0] = h[0] ^ 0x01010040ULL;  // depth 1, fanout 1, no key, 64-byte digest
  uint64_t pos = 0;
  while (len - pos > 128) {
    blake2b_compress(h, v, m, msg, pos, pos + 128, 0);
    pos = pos + 128;
  }
  for (uint64_t i = 0; i < 128; ++i) {
    uint8_t b = 0;
    if (pos + i < len) b = msg[pos + i];
    pad[i] = b;
  }
  blake2b_compress(h, v, m, pad, 0, len, 1);
  for (uint64_t i = 0; i < 8; ++i)
    for (uint64_t k = 0; k < 8; ++k) out[8 * i + k] = (uint8_t)((h[i] >> (8 * k)) & 255);
}

int main(void) {
  const uint64_t hashes = 2048ULL * BENCH_SCALE;
  const uint64_t len = 16384;
  uint64_t h[8];
  uint64_t v[16];
  uint64_t m[16];
  uint8_t pad[128];
  uint8_t digest[64];
  uint8_t *msg = (uint8_t *)malloc(len);
  for (uint64_t i = 0; i < len; ++i) msg[i] = (uint8_t)((i * 131 + 7) & 255);
  for (uint64_t i = 0; i < 64; ++i) digest[i] = 0;

  for (uint64_t k = 0; k < hashes; ++k) {
    for (uint64_t i = 0; i < 8; ++i) msg[i] = digest[i];
    blake2b(digest, msg, len, h, v, m, pad);
  }

  uint64_t r = le64(digest, 0);
  free(msg);
  printf("%llu\n", (unsigned long long)(r & 0x7fffffffffffffffULL));
  return 0;
}
