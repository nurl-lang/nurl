// benchmark-contract: x25519;rfc7748;k=u=9;iterations=1000;checksum=k-le64
//
// x25519 — RFC 7748 X25519, variable base, in the formulation the NURL
// standard library uses: the TweetNaCl ladder over the
// curve25519-donna-c64 field (five limbs at radix 2^51, 64x64->128
// products — here `u128`) and the ref10 inversion chain. RFC 7748 §5.2's
// iteration test, 1000 times. See x25519.c for the full description; this
// is the same program line for line, and x25519.nu calls the standard
// library's `x25519` instead.

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

// Every field element lives in one flat limb array `g`, addressed by its
// offset: the ladder's operations alias freely (`fmul(g, FA, FA, FC)`
// multiplies in place), which Rust's borrow rules allow only this way.
const FA: usize = 0;
const FB: usize = 5;
const FC: usize = 10;
const FD: usize = 15;
const FE: usize = 20;
const FF: usize = 25;
const FX: usize = 30;
const FK: usize = 35; // the constant 121665
const FZ2: usize = 40; // inversion scratch, five elements
const FZ9: usize = 45;
const FZ11: usize = 50;
const FZ5: usize = 55;
const FZ10: usize = 60;
const FZ50: usize = 65;
const FT: usize = 70;
const GLIMBS: usize = 75;

const M51: u64 = 0x7_ffff_ffff_ffff;

// Constant-time swap of elements p and q when b == 1.
fn sel25519(g: &mut [u64; GLIMBS], p: usize, q: usize, b: u64) {
    let c = 0u64.wrapping_sub(b);
    for i in 0..5 {
        let t = c & (g[p + i] ^ g[q + i]);
        g[p + i] = g[p + i] ^ t;
        g[q + i] = g[q + i] ^ t;
    }
}

// o = a + b, limbwise; the next multiply carries.
fn fadd(g: &mut [u64; GLIMBS], o: usize, a: usize, b: usize) {
    for i in 0..5 {
        g[o + i] = g[a + i] + g[b + i];
    }
}

// o = a - b + 2p, limbwise, so no limb goes negative.
fn fsub(g: &mut [u64; GLIMBS], o: usize, a: usize, b: usize) {
    g[o] = g[a] + 0xfffffffffffda - g[b];
    g[o + 1] = g[a + 1] + 0xffffffffffffe - g[b + 1];
    g[o + 2] = g[a + 2] + 0xffffffffffffe - g[b + 2];
    g[o + 3] = g[a + 3] + 0xffffffffffffe - g[b + 3];
    g[o + 4] = g[a + 4] + 0xffffffffffffe - g[b + 4];
}

// Five 128-bit column sums -> five 51-bit limbs at o, folding the top x19.
fn carry_out(g: &mut [u64; GLIMBS], o: usize, t0: u128, mut t1: u128, mut t2: u128, mut t3: u128, mut t4: u128) {
    let mut g0 = (t0 as u64) & M51;
    t1 = t1 + ((t0 >> 51) as u64) as u128;
    let mut g1 = (t1 as u64) & M51;
    t2 = t2 + ((t1 >> 51) as u64) as u128;
    let mut g2 = (t2 as u64) & M51;
    t3 = t3 + ((t2 >> 51) as u64) as u128;
    let g3 = (t3 as u64) & M51;
    t4 = t4 + ((t3 >> 51) as u64) as u128;
    let g4 = (t4 as u64) & M51;
    let mut c = (t4 >> 51) as u64;
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

fn m(x: u64, y: u64) -> u128 {
    (x as u128) * (y as u128)
}

// o = a * b mod p (donna-c64 fmul). o may alias a or b.
fn fmul(g: &mut [u64; GLIMBS], o: usize, a: usize, b: usize) {
    let (r0, r1, r2, r3, r4) = (g[a], g[a + 1], g[a + 2], g[a + 3], g[a + 4]);
    let (s0, s1, s2, s3, s4) = (g[b], g[b + 1], g[b + 2], g[b + 3], g[b + 4]);
    let (f1, f2, f3, f4) = (r1 * 19, r2 * 19, r3 * 19, r4 * 19);
    let t0 = m(r0, s0) + m(f4, s1) + m(f1, s4) + m(f2, s3) + m(f3, s2);
    let t1 = m(r0, s1) + m(r1, s0) + m(f4, s2) + m(f2, s4) + m(f3, s3);
    let t2 = m(r0, s2) + m(r1, s1) + m(r2, s0) + m(f4, s3) + m(f3, s4);
    let t3 = m(r0, s3) + m(r1, s2) + m(r2, s1) + m(r3, s0) + m(f4, s4);
    let t4 = m(r0, s4) + m(r1, s3) + m(r2, s2) + m(r3, s1) + m(r4, s0);
    carry_out(g, o, t0, t1, t2, t3, t4);
}

// o = a^2 mod p (donna-c64 fsquare: the cross terms doubled once).
fn fsq(g: &mut [u64; GLIMBS], o: usize, a: usize) {
    let (r0, r1, r2, r3, r4) = (g[a], g[a + 1], g[a + 2], g[a + 3], g[a + 4]);
    let (d0, d1, d2, d419) = (r0 * 2, r1 * 2, r2 * 38, r4 * 19);
    let d4 = d419 * 2;
    let r319 = r3 * 19;
    let t0 = m(r0, r0) + m(d4, r1) + m(d2, r3);
    let t1 = m(d0, r1) + m(d4, r2) + m(r3, r319);
    let t2 = m(d0, r2) + m(r1, r1) + m(d4, r3);
    let t3 = m(d0, r3) + m(d1, r2) + m(r4, d419);
    let t4 = m(d0, r4) + m(d1, r3) + m(r2, r2);
    carry_out(g, o, t0, t1, t2, t3, t4);
}

fn fcopy(g: &mut [u64; GLIMBS], o: usize, a: usize) {
    for i in 0..5 {
        g[o + i] = g[a + i];
    }
}

// o = o^(2^n): n back-to-back squarings.
fn fsqn(g: &mut [u64; GLIMBS], o: usize, n: u64) {
    for _ in 0..n {
        fsq(g, o, o);
    }
}

// io = io^(p-2) = 1/io: the ref10 addition chain.
fn inv25519(g: &mut [u64; GLIMBS], io: usize) {
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

fn le64(p: &[u8], o: usize) -> u64 {
    let mut v: u64 = 0;
    for k in 0..8 {
        v = v | ((p[o + k] as u64) << (8 * k));
    }
    v
}

// 32 little-endian bytes -> element o, the top bit dropped (fexpand).
fn unpack25519(g: &mut [u64; GLIMBS], o: usize, n: &[u8]) {
    g[o] = le64(n, 0) & M51;
    g[o + 1] = (le64(n, 6) >> 3) & M51;
    g[o + 2] = (le64(n, 12) >> 6) & M51;
    g[o + 3] = (le64(n, 19) >> 1) & M51;
    g[o + 4] = (le64(n, 24) >> 12) & M51;
}

// Element n fully reduced mod p -> 32 little-endian bytes (fcontract).
fn pack25519(out: &mut [u8; 32], g: &[u64; GLIMBS], n: usize) {
    let (mut h0, mut h1, mut h2, mut h3, mut h4) = (g[n], g[n + 1], g[n + 2], g[n + 3], g[n + 4]);
    for _ in 0..2 {
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
    h0 = h0 + 0x7ffffffffffed;
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
    let w0 = h0 | (h1 << 51);
    let w1 = (h1 >> 13) | (h2 << 38);
    let w2 = (h2 >> 26) | (h3 << 25);
    let w3 = (h3 >> 39) | (h4 << 12);
    for k in 0..8 {
        out[k] = ((w0 >> (8 * k)) & 255) as u8;
        out[k + 8] = ((w1 >> (8 * k)) & 255) as u8;
        out[k + 16] = ((w2 >> (8 * k)) & 255) as u8;
        out[k + 24] = ((w3 >> (8 * k)) & 255) as u8;
    }
}

// q = X25519(n, p): scalar n (clamped into z), u-coordinate p. `g` and
// `z` (32 bytes) are the caller's scratch.
fn x25519(q: &mut [u8; 32], n: &[u8; 32], p: &[u8; 32], g: &mut [u64; GLIMBS], z: &mut [u8; 32]) {
    for i in 0..32 {
        z[i] = n[i];
    }
    z[31] = (n[31] & 127) | 64;
    z[0] = n[0] & 248;
    unpack25519(g, FX, p);
    for i in 0..5 {
        g[FA + i] = 0;
        g[FB + i] = g[FX + i];
        g[FC + i] = 0;
        g[FD + i] = 0;
    }
    g[FA] = 1;
    g[FD] = 1;
    let mut i: i64 = 254;
    while i >= 0 {
        let r = ((z[(i >> 3) as usize] as u64) >> (i & 7)) & 1;
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
        i = i - 1;
    }
    inv25519(g, FC);
    fmul(g, FA, FA, FC);
    pack25519(q, g, FA);
}

fn main() {
    let iterations: u64 = 1000 * BENCH_SCALE;
    let mut g = [0u64; GLIMBS];
    let mut z = [0u8; 32];
    let mut k = [0u8; 32];
    let mut u = [0u8; 32];
    let mut r = [0u8; 32];
    g[FK] = 121665;
    k[0] = 9;
    u[0] = 9;

    for _ in 0..iterations {
        x25519(&mut r, &k, &u, &mut g, &mut z);
        for i in 0..32 {
            u[i] = k[i];
            k[i] = r[i];
        }
    }

    let v = le64(&k, 0);
    println!("{}", v & 0x7fff_ffff_ffff_ffff);
}
