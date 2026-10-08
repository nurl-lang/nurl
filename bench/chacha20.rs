// benchmark-contract: chacha20;rfc8439;key=00..1f;nonce=000000090000004a00000000;counter=1;buffer=16384;passes=1024;checksum=fnv1a64-words
//
// chacha20 — the RFC 8439 stream cipher, the portable scalar formulation:
// a 16 KiB buffer encrypted in place 1024 times, the block counter running
// on across passes. See chacha20.c for the full description; this is the
// same program line for line, and chacha20.nu calls the standard
// library's `chacha20_xor` instead.

// The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
const BENCH_SCALE: u64 = 1;

fn rotl32(x: u32, n: u32) -> u32 {
    (x << n) | (x >> (32 - n))
}

fn quarter(x: &mut [u32; 16], a: usize, b: usize, c: usize, d: usize) {
    x[a] = x[a].wrapping_add(x[b]);
    x[d] = rotl32(x[d] ^ x[a], 16);
    x[c] = x[c].wrapping_add(x[d]);
    x[b] = rotl32(x[b] ^ x[c], 12);
    x[a] = x[a].wrapping_add(x[b]);
    x[d] = rotl32(x[d] ^ x[a], 8);
    x[c] = x[c].wrapping_add(x[d]);
    x[b] = rotl32(x[b] ^ x[c], 7);
}

// One 64-byte keystream block from the input state `inp`, XORed into
// buf[off .. off+63]. `x` is the caller's 16-word working state.
fn chacha20_block_xor(inp: &[u32; 16], x: &mut [u32; 16], buf: &mut [u8], off: usize) {
    for i in 0..16 {
        x[i] = inp[i];
    }
    for _ in 0..10 {
        quarter(x, 0, 4, 8, 12);
        quarter(x, 1, 5, 9, 13);
        quarter(x, 2, 6, 10, 14);
        quarter(x, 3, 7, 11, 15);
        quarter(x, 0, 5, 10, 15);
        quarter(x, 1, 6, 11, 12);
        quarter(x, 2, 7, 8, 13);
        quarter(x, 3, 4, 9, 14);
    }
    for i in 0..16 {
        let w = x[i].wrapping_add(inp[i]);
        let p = off + 4 * i;
        buf[p] = buf[p] ^ (w & 255) as u8;
        buf[p + 1] = buf[p + 1] ^ ((w >> 8) & 255) as u8;
        buf[p + 2] = buf[p + 2] ^ ((w >> 16) & 255) as u8;
        buf[p + 3] = buf[p + 3] ^ ((w >> 24) & 255) as u8;
    }
}

fn le32(p: &[u8], o: usize) -> u32 {
    (p[o] as u32) | ((p[o + 1] as u32) << 8) | ((p[o + 2] as u32) << 16) | ((p[o + 3] as u32) << 24)
}

fn le64(p: &[u8], o: usize) -> u64 {
    let mut v: u64 = 0;
    for k in 0..8 {
        v = v | ((p[o + k] as u64) << (8 * k));
    }
    v
}

// XOR the ChaCha20 keystream for (key, counter, nonce) into buf[0..len-1].
// `inp` and `x` (16 words) and `ks` (64 bytes) are the caller's scratch.
fn chacha20_xor(
    buf: &mut [u8],
    len: usize,
    key: &[u8],
    counter: u32,
    nonce: &[u8],
    inp: &mut [u32; 16],
    x: &mut [u32; 16],
    ks: &mut [u8; 64],
) {
    inp[0] = 0x61707865;
    inp[1] = 0x3320646e;
    inp[2] = 0x79622d32;
    inp[3] = 0x6b206574;
    for i in 0..8 {
        inp[4 + i] = le32(key, 4 * i);
    }
    inp[12] = counter;
    inp[13] = le32(nonce, 0);
    inp[14] = le32(nonce, 4);
    inp[15] = le32(nonce, 8);
    let mut off = 0usize;
    while off + 64 <= len {
        chacha20_block_xor(inp, x, buf, off);
        inp[12] = inp[12].wrapping_add(1);
        off = off + 64;
    }
    if off < len {
        // a final partial block: keystream into ks, then byte by byte
        for i in 0..64 {
            ks[i] = 0;
        }
        chacha20_block_xor(inp, x, ks, 0);
        let mut i = 0usize;
        while off + i < len {
            buf[off + i] = buf[off + i] ^ ks[i];
            i = i + 1;
        }
    }
}

fn main() {
    let passes: u64 = 1024 * BENCH_SCALE;
    let len: usize = 16384;
    let mut inp = [0u32; 16];
    let mut x = [0u32; 16];
    let mut ks = [0u8; 64];
    let mut key = [0u8; 32];
    let mut nonce = [0u8; 12];
    for i in 0..32 {
        key[i] = i as u8;
    }
    nonce[3] = 0x09;
    nonce[7] = 0x4a;

    let mut buf = vec![0u8; len];
    for i in 0..len {
        buf[i] = (i & 255) as u8;
    }

    // the block counter runs on across passes: pass p starts at 1 + p*256
    for pass in 0..passes {
        let counter = (1 + pass * (len as u64 / 64)) as u32;
        chacha20_xor(&mut buf, len, &key, counter, &nonce, &mut inp, &mut x, &mut ks);
    }

    let mut h: u64 = 0xcbf29ce484222325;
    let mut i = 0usize;
    while i < len {
        h = (h ^ le64(&buf, i)).wrapping_mul(0x100000001b3);
        i = i + 8;
    }
    println!("{}", h & 0x7fff_ffff_ffff_ffff);
}
