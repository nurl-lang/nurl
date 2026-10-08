// benchmark-contract: poly1305;rfc8439;message=16384;macs=4096;key=chained;checksum=tag-le64
//
// poly1305 — the RFC 8439 one-time authenticator in the poly1305-donna-64
// formulation the NURL standard library uses: three limbs at radix 2^44,
// nine 64x64->128 products a block (here `u128`). A 16 KiB message is
// MACed 4096 times, every tag XORed back into the key. See poly1305.c for
// the full description; this is the same program line for line, and
// poly1305.nu calls the standard library's `poly1305_mac` instead.

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

const M44: u64 = 0xfff_ffff_ffff;
const M42: u64 = 0x3ff_ffff_ffff;

fn le64(p: &[u8], o: usize) -> u64 {
    let mut v: u64 = 0;
    for k in 0..8 {
        v = v | ((p[o + k] as u64) << (8 * k));
    }
    v
}

// tag[0..15] = Poly1305(key[0..31], msg[0..len-1]).
fn poly1305_mac(tag: &mut [u8; 16], key: &[u8], msg: &[u8], len: usize) {
    let kt0 = le64(key, 0);
    let kt1 = le64(key, 8);
    let r0 = kt0 & 0xffc0fffffff;
    let r1 = ((kt0 >> 44) | (kt1 << 20)) & 0xfffffc0ffff;
    let r2 = (kt1 >> 24) & 0x00ffffffc0f;
    let s1 = r1 * 20;
    let s2 = r2 * 20;
    let mut h0: u64 = 0;
    let mut h1: u64 = 0;
    let mut h2: u64 = 0;

    let mut off = 0usize;
    while off < len {
        let rem = len - off;
        let mut t0: u64 = 0;
        let mut t1: u64 = 0;
        let mut hibit: u64 = 1 << 40;
        if rem >= 16 {
            t0 = le64(msg, off);
            t1 = le64(msg, off + 8);
        } else {
            // tail: the bytes, the 0x01 marker after them, zeros; no hibit
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
            hibit = 0;
        }
        h0 = h0 + (t0 & M44);
        h1 = h1 + (((t0 >> 44) | (t1 << 20)) & M44);
        h2 = h2 + ((t1 >> 24) & M42) + hibit;

        let d0 = (h0 as u128) * (r0 as u128) + (h1 as u128) * (s2 as u128) + (h2 as u128) * (s1 as u128);
        let mut d1 = (h0 as u128) * (r1 as u128) + (h1 as u128) * (r0 as u128) + (h2 as u128) * (s2 as u128);
        let mut d2 = (h0 as u128) * (r2 as u128) + (h1 as u128) * (r1 as u128) + (h2 as u128) * (r0 as u128);

        let mut c = (d0 >> 44) as u64;
        h0 = (d0 as u64) & M44;
        d1 = d1 + c as u128;
        c = (d1 >> 44) as u64;
        h1 = (d1 as u64) & M44;
        d2 = d2 + c as u128;
        c = (d2 >> 42) as u64;
        h2 = (d2 as u64) & M42;
        h0 = h0 + c * 5;
        c = h0 >> 44;
        h0 = h0 & M44;
        h1 = h1 + c;

        off = off + 16;
    }

    // fully carry h
    let mut c = h1 >> 44;
    h1 = h1 & M44;
    h2 = h2 + c;
    c = h2 >> 42;
    h2 = h2 & M42;
    h0 = h0 + c * 5;
    c = h0 >> 44;
    h0 = h0 & M44;
    h1 = h1 + c;

    // g = h + 5 - 2^130; keep h if g borrowed (h < p), else take g
    let mut g0 = h0 + 5;
    c = g0 >> 44;
    g0 = g0 & M44;
    let mut g1 = h1 + c;
    c = g1 >> 44;
    g1 = g1 & M44;
    let mut g2 = (h2 + c).wrapping_sub(1 << 42);
    let mask = (g2 >> 63).wrapping_sub(1);
    g0 = g0 & mask;
    g1 = g1 & mask;
    g2 = g2 & mask;
    let imask = !mask;
    h0 = (h0 & imask) | g0;
    h1 = (h1 & imask) | g1;
    h2 = (h2 & imask) | g2;

    // tag = (h + s) mod 2^128
    let st0 = le64(key, 16);
    let st1 = le64(key, 24);
    let mut f0 = h0 | (h1 << 44);
    let mut f1 = (h1 >> 20) | (h2 << 24);
    f0 = f0.wrapping_add(st0);
    f1 = f1.wrapping_add(st1).wrapping_add(if f0 < st0 { 1 } else { 0 });
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
