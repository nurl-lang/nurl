// benchmark-contract: poly1305;rfc8439;message=16384;macs=4096;key=chained;checksum=tag-le64
//
// poly1305 — the RFC 8439 one-time authenticator in the radix-2^64
// formulation the NURL standard library uses: the accumulator in two
// 64-bit words and a few bits above, four 64x64->128 products a block
// (here `u128`) and two small ones. A 16 KiB message is MACed 4096 times,
// every tag XORed back into the key. See poly1305.c for the full
// description; this is the same program line for line, and poly1305.nu
// calls the standard library's `poly1305_mac` instead.

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

fn le64(p: &[u8], o: usize) -> u64 {
    let mut v: u64 = 0;
    for k in 0..8 {
        v = v | ((p[o + k] as u64) << (8 * k));
    }
    v
}

// h = (h + m + pad * 2^128) * r, partially reduced mod 2^130 - 5 (h2 < 8)
fn poly_block(h: &mut [u64; 3], t0: u64, t1: u64, pad: u64, r0: u64, r1: u64, s1: u64) {
    let mut a = (h[0] as u128) + (t0 as u128);
    let a0 = a as u64;
    a = (h[1] as u128) + (t1 as u128) + ((a >> 64) as u128);
    let a1 = a as u64;
    let a2 = h[2] + ((a >> 64) as u64) + pad;

    let d0 = (a0 as u128) * (r0 as u128) + (a1 as u128) * (s1 as u128);
    let mut d1 = (a0 as u128) * (r1 as u128) + (a1 as u128) * (r0 as u128) + ((a2 * s1) as u128);
    let d2 = a2 * r0;

    d1 = d1 + ((d0 >> 64) as u128);
    let g2 = d2 + ((d1 >> 64) as u64);
    let c = (g2 & !3u64) + (g2 >> 2); // c * 2^130 = 5c
    let mut e = ((d0 as u64) as u128) + (c as u128);
    h[0] = e as u64;
    e = ((d1 as u64) as u128) + ((e >> 64) as u128);
    h[1] = e as u64;
    h[2] = (g2 & 3) + ((e >> 64) as u64);
}

// tag[0..15] = Poly1305(key[0..31], msg[0..len-1]).
fn poly1305_mac(tag: &mut [u8; 16], key: &[u8], msg: &[u8], len: usize) {
    let r0 = le64(key, 0) & 0x0fff_fffc_0fff_ffff;
    let r1 = le64(key, 8) & 0x0fff_fffc_0fff_fffc;
    let s1 = r1 + (r1 >> 2);
    let mut h = [0u64; 3];

    let mut off = 0usize;
    let full = len & !15usize;
    while off < full {
        poly_block(&mut h, le64(msg, off), le64(msg, off + 8), 1, r0, r1, s1);
        off = off + 16;
    }
    if off < len {
        // tail: the bytes, the 0x01 marker after them, zeros; no 2^128 bit
        let rem = len - off;
        let mut t0: u64 = 0;
        let mut t1: u64 = 0;
        for j in 0..=rem {
            let mut bv: u64 = 1;
            if j < rem {
                bv = msg[off + j] as u64;
            }
            if j < 8 {
                t0 = t0 | (bv << (8 * j));
            } else {
                t1 = t1 | (bv << (8 * (j - 8)));
            }
        }
        poly_block(&mut h, t0, t1, 0, r0, r1, s1);
    }

    // h + 5 reaches 2^130 exactly when h >= p; then its low 128 bits are h - p
    let mut g = (h[0] as u128) + 5;
    let g0 = g as u64;
    g = (h[1] as u128) + ((g >> 64) as u128);
    let g1 = g as u64;
    let g2 = h[2] + ((g >> 64) as u64);
    let mask = 0u64.wrapping_sub(g2 >> 2);
    let mut f0 = (h[0] & !mask) | (g0 & mask);
    let mut f1 = (h[1] & !mask) | (g1 & mask);

    // tag = (h + s) mod 2^128
    let w = (f0 as u128) + (le64(key, 16) as u128);
    f0 = w as u64;
    f1 = f1.wrapping_add(le64(key, 24)).wrapping_add((w >> 64) as u64);
    for k in 0..8 {
        tag[k] = ((f0 >> (8 * k)) & 255) as u8;
        tag[k + 8] = ((f1 >> (8 * k)) & 255) as u8;
    }
}

fn main() {
    let macs: u64 = 4096 * BENCH_SCALE;
    let len: usize = 16384;
    let mut tag = [0u8; 16];
    let mut key = [0u8; 32];
    for i in 0..32 {
        key[i] = ((i * 7 + 3) & 255) as u8;
    }
    let mut msg = vec![0u8; len];
    for i in 0..len {
        msg[i] = ((i * 31 + 17) & 255) as u8;
    }

    for _ in 0..macs {
        poly1305_mac(&mut tag, &key, &msg, len);
        for i in 0..16 {
            key[i] = key[i] ^ tag[i];
            key[i + 16] = key[i + 16] ^ tag[i];
        }
    }

    let v = le64(&tag, 0);
    println!("{}", v & 0x7fff_ffff_ffff_ffff);
}
