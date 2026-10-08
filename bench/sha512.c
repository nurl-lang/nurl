// benchmark-contract: sha512;fips180-4;message=16384;hashes=1024;chain=digest[0..8]->message[0..8];checksum=digest-be64
//
// sha512 — FIPS 180-4 SHA-512, scalar. A 16 KiB message is hashed 1024
// times (16 MiB); before each hash the previous digest's first eight
// bytes overwrite the message's first eight, so every hash depends on the
// last and none can be hoisted. Each 128-byte block is an 80-word message
// schedule then 80 rounds of 64-bit rotate/xor/add — a long serial chain
// through the eight working variables, the shape of every SHA-2 core.
//
// Contract: the process prints exactly one line — the final digest's
// first eight bytes as a big-endian integer, masked to 63 bits — and
// nothing else. `bench/bench.sh` gates on the NURL, C and Rust
// implementations printing the same line before it reports a timing.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
#define BENCH_SCALE 1ULL

static const uint64_t K[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL};

static uint64_t rotr64(uint64_t x, uint64_t n) { return (x >> n) | (x << (64 - n)); }

static uint64_t be64(const uint8_t *p, uint64_t o) {
  uint64_t v = 0;
  for (uint64_t k = 0; k < 8; ++k) v = (v << 8) | (uint64_t)p[o + k];
  return v;
}

// One 128-byte block at blk[o..o+127] into the state s[0..7]; `w` is the
// caller's 80-word schedule scratch.
static void sha512_block(uint64_t *s, uint64_t *w, const uint8_t *blk, uint64_t o) {
  for (uint64_t i = 0; i < 16; ++i) w[i] = be64(blk, o + 8 * i);
  for (uint64_t i = 16; i < 80; ++i) {
    uint64_t w15 = w[i - 15];
    uint64_t w2 = w[i - 2];
    uint64_t s0 = rotr64(w15, 1) ^ rotr64(w15, 8) ^ (w15 >> 7);
    uint64_t s1 = rotr64(w2, 19) ^ rotr64(w2, 61) ^ (w2 >> 6);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint64_t a = s[0], b = s[1], c = s[2], d = s[3];
  uint64_t e = s[4], f = s[5], g = s[6], h = s[7];
  for (uint64_t i = 0; i < 80; ++i) {
    uint64_t S1 = rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41);
    uint64_t ch = (e & f) ^ (~e & g);
    uint64_t t1 = h + S1 + ch + K[i] + w[i];
    uint64_t S0 = rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39);
    uint64_t mj = (a & b) ^ (a & c) ^ (b & c);
    uint64_t t2 = S0 + mj;
    h = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + t2;
  }
  s[0] = s[0] + a;
  s[1] = s[1] + b;
  s[2] = s[2] + c;
  s[3] = s[3] + d;
  s[4] = s[4] + e;
  s[5] = s[5] + f;
  s[6] = s[6] + g;
  s[7] = s[7] + h;
}

// out[0..63] = SHA-512(msg[0..len-1]). `s` (8 words), `w` (80 words) and
// `pad` (256 bytes, the one or two padded final blocks) are scratch.
static void sha512(uint8_t *out, const uint8_t *msg, uint64_t len, uint64_t *s, uint64_t *w,
                   uint8_t *pad) {
  s[0] = 0x6a09e667f3bcc908ULL;
  s[1] = 0xbb67ae8584caa73bULL;
  s[2] = 0x3c6ef372fe94f82bULL;
  s[3] = 0xa54ff53a5f1d36f1ULL;
  s[4] = 0x510e527fade682d1ULL;
  s[5] = 0x9b05688c2b3e6c1fULL;
  s[6] = 0x1f83d9abfb41bd6bULL;
  s[7] = 0x5be0cd19137e2179ULL;
  uint64_t pos = 0;
  while (len - pos >= 128) {
    sha512_block(s, w, msg, pos);
    pos = pos + 128;
  }
  // tail + 0x80 + zeros + 128-bit big-endian bit length (high half 0)
  uint64_t rest = len - pos;
  uint64_t total = 128;
  if (rest >= 112) total = 256;
  for (uint64_t i = 0; i < total; ++i) {
    uint8_t b = 0;
    if (i < rest) b = msg[pos + i];
    if (i == rest) b = 0x80;
    pad[i] = b;
  }
  uint64_t bits = len * 8;
  for (uint64_t k = 0; k < 8; ++k) pad[total - 1 - k] = (uint8_t)((bits >> (8 * k)) & 255);
  sha512_block(s, w, pad, 0);
  if (total == 256) sha512_block(s, w, pad, 128);
  for (uint64_t i = 0; i < 8; ++i)
    for (uint64_t k = 0; k < 8; ++k) out[8 * i + k] = (uint8_t)((s[i] >> (56 - 8 * k)) & 255);
}

int main(void) {
  const uint64_t hashes = 1024ULL * BENCH_SCALE;
  const uint64_t len = 16384;
  uint64_t s[8];
  uint64_t w[80];
  uint8_t pad[256];
  uint8_t digest[64];
  uint8_t *msg = (uint8_t *)malloc(len);
  for (uint64_t i = 0; i < len; ++i) msg[i] = (uint8_t)((i * 131 + 7) & 255);
  for (uint64_t i = 0; i < 64; ++i) digest[i] = 0;

  for (uint64_t k = 0; k < hashes; ++k) {
    for (uint64_t i = 0; i < 8; ++i) msg[i] = digest[i];
    sha512(digest, msg, len, s, w, pad);
  }

  uint64_t v = be64(digest, 0);
  free(msg);
  printf("%llu\n", (unsigned long long)(v & 0x7fffffffffffffffULL));
  return 0;
}
