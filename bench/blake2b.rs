// benchmark-contract: blake2b;rfc7693;outlen=64;unkeyed;message=16384;hashes=2048;chain=digest[0..8]->message[0..8];checksum=digest-le64
//
// blake2b — RFC 7693 BLAKE2b-512, unkeyed, scalar: a 16 KiB message
// hashed 2048 times, each hash's first eight digest bytes written into the
// next message. See blake2b.c for the full description; this is the same
// program line for line, and blake2b.nu calls the standard library's
// `blake2b512_pure` instead.

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

const IV: [u64; 8] = [
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
];

const SIGMA: [u8; 192] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
    11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
    7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
    9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
    2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
    12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
    13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
    6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
    10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
];

fn rotr64(x: u64, n: u32) -> u64 {
    (x >> n) | (x << (64 - n))
}

fn le64(p: &[u8], o: usize) -> u64 {
    let mut v: u64 = 0;
    for k in 0..8 {
        v = v | ((p[o + k] as u64) << (8 * k));
    }
    v
}

fn mix(v: &mut [u64; 16], a: usize, b: usize, c: usize, d: usize, x: u64, y: u64) {
    v[a] = v[a].wrapping_add(v[b]).wrapping_add(x);
    v[d] = rotr64(v[d] ^ v[a], 32);
    v[c] = v[c].wrapping_add(v[d]);
    v[b] = rotr64(v[b] ^ v[c], 24);
    v[a] = v[a].wrapping_add(v[b]).wrapping_add(y);
    v[d] = rotr64(v[d] ^ v[a], 16);
    v[c] = v[c].wrapping_add(v[d]);
    v[b] = rotr64(v[b] ^ v[c], 63);
}

// Compress the 128-byte block at blk[o..o+127] into h[0..7]. `t` is the
// byte count so far (the high counter word is always 0 here), `last` is 1
// for the final block. `v` (16 words) and `m` (16 words) are scratch.
fn blake2b_compress(h: &mut [u64; 8], v: &mut [u64; 16], m: &mut [u64; 16], blk: &[u8], o: usize, t: u64, last: u64) {
    for i in 0..16 {
        m[i] = le64(blk, o + 8 * i);
    }
    for i in 0..8 {
        v[i] = h[i];
        v[i + 8] = IV[i];
    }
    v[12] = v[12] ^ t;
    if last == 1 {
        v[14] = !v[14];
    }
    for r in 0..12 {
        let s = &SIGMA[16 * r..16 * r + 16];
        mix(v, 0, 4, 8, 12, m[s[0] as usize], m[s[1] as usize]);
        mix(v, 1, 5, 9, 13, m[s[2] as usize], m[s[3] as usize]);
        mix(v, 2, 6, 10, 14, m[s[4] as usize], m[s[5] as usize]);
        mix(v, 3, 7, 11, 15, m[s[6] as usize], m[s[7] as usize]);
        mix(v, 0, 5, 10, 15, m[s[8] as usize], m[s[9] as usize]);
        mix(v, 1, 6, 11, 12, m[s[10] as usize], m[s[11] as usize]);
        mix(v, 2, 7, 8, 13, m[s[12] as usize], m[s[13] as usize]);
        mix(v, 3, 4, 9, 14, m[s[14] as usize], m[s[15] as usize]);
    }
    for i in 0..8 {
        h[i] = h[i] ^ v[i] ^ v[i + 8];
    }
}

// out[0..63] = BLAKE2b-512(msg[0..len-1]). `h` (8 words), `v` and `m`
// (16 words each) and `pad` (128 bytes, the zero-padded last block) are
// scratch.
fn blake2b(out: &mut [u8; 64], msg: &[u8], len: usize, h: &mut [u64; 8], v: &mut [u64; 16], m: &mut [u64; 16], pad: &mut [u8; 128]) {
    for i in 0..8 {
        h[i] = IV[i];
    }
    h[0] = h[0] ^ 0x01010040; // depth 1, fanout 1, no key, 64-byte digest
    let mut pos = 0usize;
    while len - pos > 128 {
        blake2b_compress(h, v, m, msg, pos, (pos + 128) as u64, 0);
        pos = pos + 128;
    }
    for i in 0..128 {
        let mut b: u8 = 0;
        if pos + i < len {
            b = msg[pos + i];
        }
        pad[i] = b;
    }
    blake2b_compress(h, v, m, pad, 0, len as u64, 1);
    for i in 0..8 {
        for k in 0..8 {
            out[8 * i + k] = ((h[i] >> (8 * k)) & 255) as u8;
        }
    }
}

fn main() {
    let hashes: u64 = 2048 * BENCH_SCALE;
    let len: usize = 16384;
    let mut h = [0u64; 8];
    let mut v = [0u64; 16];
    let mut m = [0u64; 16];
    let mut pad = [0u8; 128];
    let mut digest = [0u8; 64];
    let mut msg = vec![0u8; len];
    for i in 0..len {
        msg[i] = ((i * 131 + 7) & 255) as u8;
    }

    for _ in 0..hashes {
        for i in 0..8 {
            msg[i] = digest[i];
        }
        blake2b(&mut digest, &msg, len, &mut h, &mut v, &mut m, &mut pad);
    }

    let r = le64(&digest, 0);
    println!("{}", r & 0x7fff_ffff_ffff_ffff);
}
