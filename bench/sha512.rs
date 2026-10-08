// benchmark-contract: sha512;fips180-4;message=16384;hashes=1024;chain=digest[0..8]->message[0..8];checksum=digest-be64
//
// sha512 — FIPS 180-4 SHA-512, scalar: a 16 KiB message hashed 1024
// times, each hash's first eight digest bytes written into the next
// message. See sha512.c for the full description; this is the same
// program line for line, and sha512.nu calls the standard library's
// `sha512_pure` instead.

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

const K: [u64; 80] = [
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
    0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
    0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
    0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
    0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
    0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
    0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
    0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
    0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
    0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
    0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
    0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
    0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
    0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
    0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
];

fn rotr64(x: u64, n: u32) -> u64 {
    (x >> n) | (x << (64 - n))
}

fn be64(p: &[u8], o: usize) -> u64 {
    let mut v: u64 = 0;
    for k in 0..8 {
        v = (v << 8) | (p[o + k] as u64);
    }
    v
}

// One 128-byte block at blk[o..o+127] into the state s[0..7]; `w` is the
// caller's 80-word schedule scratch.
fn sha512_block(s: &mut [u64; 8], w: &mut [u64; 80], blk: &[u8], o: usize) {
    for i in 0..16 {
        w[i] = be64(blk, o + 8 * i);
    }
    for i in 16..80 {
        let w15 = w[i - 15];
        let w2 = w[i - 2];
        let s0 = rotr64(w15, 1) ^ rotr64(w15, 8) ^ (w15 >> 7);
        let s1 = rotr64(w2, 19) ^ rotr64(w2, 61) ^ (w2 >> 6);
        w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
    }
    let mut a = s[0];
    let mut b = s[1];
    let mut c = s[2];
    let mut d = s[3];
    let mut e = s[4];
    let mut f = s[5];
    let mut g = s[6];
    let mut h = s[7];
    for i in 0..80 {
        let s1 = rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41);
        let ch = (e & f) ^ (!e & g);
        let t1 = h.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
        let s0 = rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39);
        let mj = (a & b) ^ (a & c) ^ (b & c);
        let t2 = s0.wrapping_add(mj);
        h = g;
        g = f;
        f = e;
        e = d.wrapping_add(t1);
        d = c;
        c = b;
        b = a;
        a = t1.wrapping_add(t2);
    }
    s[0] = s[0].wrapping_add(a);
    s[1] = s[1].wrapping_add(b);
    s[2] = s[2].wrapping_add(c);
    s[3] = s[3].wrapping_add(d);
    s[4] = s[4].wrapping_add(e);
    s[5] = s[5].wrapping_add(f);
    s[6] = s[6].wrapping_add(g);
    s[7] = s[7].wrapping_add(h);
}

// out[0..63] = SHA-512(msg[0..len-1]). `s` (8 words), `w` (80 words) and
// `pad` (256 bytes, the one or two padded final blocks) are scratch.
fn sha512(out: &mut [u8; 64], msg: &[u8], len: usize, s: &mut [u64; 8], w: &mut [u64; 80], pad: &mut [u8; 256]) {
    s[0] = 0x6a09e667f3bcc908;
    s[1] = 0xbb67ae8584caa73b;
    s[2] = 0x3c6ef372fe94f82b;
    s[3] = 0xa54ff53a5f1d36f1;
    s[4] = 0x510e527fade682d1;
    s[5] = 0x9b05688c2b3e6c1f;
    s[6] = 0x1f83d9abfb41bd6b;
    s[7] = 0x5be0cd19137e2179;
    let mut pos = 0usize;
    while len - pos >= 128 {
        sha512_block(s, w, msg, pos);
        pos = pos + 128;
    }
    // tail + 0x80 + zeros + 128-bit big-endian bit length (high half 0)
    let rest = len - pos;
    let mut total = 128usize;
    if rest >= 112 {
        total = 256;
    }
    for i in 0..total {
        let mut b: u8 = 0;
        if i < rest {
            b = msg[pos + i];
        }
        if i == rest {
            b = 0x80;
        }
        pad[i] = b;
    }
    let bits = (len as u64) * 8;
    for k in 0..8 {
        pad[total - 1 - k] = ((bits >> (8 * k)) & 255) as u8;
    }
    sha512_block(s, w, pad, 0);
    if total == 256 {
        sha512_block(s, w, pad, 128);
    }
    for i in 0..8 {
        for k in 0..8 {
            out[8 * i + k] = ((s[i] >> (56 - 8 * k)) & 255) as u8;
        }
    }
}

fn main() {
    let hashes: u64 = 1024 * BENCH_SCALE;
    let len: usize = 16384;
    let mut s = [0u64; 8];
    let mut w = [0u64; 80];
    let mut pad = [0u8; 256];
    let mut digest = [0u8; 64];
    let mut msg = vec![0u8; len];
    for i in 0..len {
        msg[i] = ((i * 131 + 7) & 255) as u8;
    }

    for _ in 0..hashes {
        for i in 0..8 {
            msg[i] = digest[i];
        }
        sha512(&mut digest, &msg, len, &mut s, &mut w, &mut pad);
    }

    let v = be64(&digest, 0);
    println!("{}", v & 0x7fff_ffff_ffff_ffff);
}
