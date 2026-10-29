// stdlib/std/chacha20poly1305.nu — pure-NURL ChaCha20, Poly1305, and the
// ChaCha20-Poly1305 AEAD (RFC 8439). No OpenSSL, no FFI.
//
// This is the record-protection half of a pure TLS 1.3 stack (the
// TLS_CHACHA20_POLY1305_SHA256 cipher suite), and is equally usable for
// Noise / age / any AEAD need on a host with nothing installed.
//
// ChaCha20 runs on vector lanes on every little-endian host — eight
// blocks a pass over `v256` on x86-64-v3, four over `v128` where vectors
// are native, then two, then one — with a scalar reference path over u32
// words for a big-endian target.
// Poly1305 is radix 2^64: a two-word r and a three-word accumulator, so a
// block is four full 64×64→128 products (nurl_mac_lo/_hi and nurl_umulhi
// supply the halves) plus two small ones, against the nine of the
// radix-2^44 donna-64 form it replaced.
//
// Public surface:
//   ( chacha20_block key counter nonce )      → ( Vec u )  64-byte block
//   ( chacha20_xor key counter nonce data )   → ( Vec u )  stream cipher
//   ( chacha20_xor_range k c n data off len ) → ( Vec u )  … over a range
//   ( poly1305_mac otk msg )                  → ( Vec u )  16-byte tag
//   ( aead_encrypt key nonce aad plaintext )  → ( Vec u )  ciphertext||tag
//   ( aead_decrypt key nonce aad ct_and_tag ) → ?( Vec u ) None if forged
//   ( chacha20poly1305_seal_in key iv seq buf aad_at data_at )     → b
//   ( chacha20poly1305_open_in key iv seq buf aad_at data_at end ) → b
//       in place, the nonce iv ⊕ seq (TLS 1.3 / QUIC): see below
//
//   key  = 32 bytes, nonce = 12 bytes, counter = i (block counter).

$ `stdlib/core/vec.nu`

// ── byte / word helpers ───────────────────────────────────────────
@ __cc_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ __push_le32 ( Vec u ) out i w → v {
    ( vec_push [u] out # u & w 255 )
    ( vec_push [u] out # u & >> w 8 255 )
    ( vec_push [u] out # u & >> w 16 255 )
    ( vec_push [u] out # u & >> w 24 255 )
}

// 4 little-endian bytes at offset → i (0 .. 2^32-1).
@ __ld32 ( Vec u ) v i off → i {
    ^ | | | ( __cc_bget v off ) << ( __cc_bget v + off 1 ) 8 << ( __cc_bget v + off 2 ) 16 << ( __cc_bget v + off 3 ) 24
}

// ── ChaCha20 ──────────────────────────────────────────────────────
// The round function lives once, inside `chacha20_xor_range` below, with
// the sixteen state words held in locals. The separate quarter-round /
// state-vector helpers this file used to carry for `chacha20_block` were
// the accessor-based second copy of it, and are gone.

// Does a 64-bit store land in memory low byte first? The block loop
// below combines two 32-bit keystream words into one machine word and
// stores it whole, which is only the same bytes on a little-endian
// machine. Every target NURL builds for is one, but this file is where
// getting it wrong would mean silently wrong ciphertext rather than a
// build error, so it asks instead of assuming — once, into a global, not
// once per record. (Two threads racing here both write the same answer.)
: ~ i g_cc_le -1

@ __le_words → i {
    ? >= g_cc_le 0 { ^ g_cc_le } {}
    : ( Vec u ) w ( vec_zeroed [u] 8 )
    : *u p ( vec_data [u] w )
    ( nurl_poke # s p 0 1 )
    = g_cc_le ? == # i . p 0 1 1 0
    ^ g_cc_le
}

// The output Vec of the XOR kernels, `n` long, with room after it for
// the 16-byte tag an AEAD appends (no regrow) and, 16-aligned past that,
// `scratch` bytes of keystream scratch: one allocation, not two.
@ __xor_out i n i scratch → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] + ( __xor_scratch_at n ) scratch )
    : b _ol ( vec_set_len [u] out n )
    ^ out
}

@ __xor_scratch_at i n → i { ^ & + n 31 -16 }

// `n` zero bytes — the plaintext that turns the XOR kernel into a plain
// keystream generator.
@ __zeros i n → ( Vec u ) {
    : ( Vec u ) z ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] z # u 0 ) = k + k 1 }
    ^ z
}

// The 64-byte keystream block for (key, counter, nonce). Keystream is
// what the XOR kernel produces against a zero plaintext, so this goes
// through `chacha20_xor_range` rather than keeping a second, slower copy
// of the round function: the accessor-based version this replaced ran
// ~960 bounds-checked Vec calls a block, and the AEAD below needs one
// block PER RECORD for the Poly1305 one-time key.
@ chacha20_block ( Vec u ) key i counter ( Vec u ) nonce → ( Vec u ) {
    : ( Vec u ) z ( __zeros 64 )
    : ( Vec u ) out ( chacha20_xor_range key counter nonce z 0 64 )
    ^ out
}

// Encrypt / decrypt `data` with the ChaCha20 keystream beginning at the
// given block counter. (XOR is its own inverse.)
//
// This is the whole cost of a TLS transfer, so it is written for the
// register allocator: the sixteen state words are LOCALS (the previous
// version made ~960 bounds-checked Vec accessor calls per 64-byte
// block), the key/nonce words are hoisted out of the block loop, the
// output is written through raw pointers, and a block allocates
// nothing. Measured on one core this is ~9x the accessor version, and
// it is what takes a pure-NURL TLS download from ~27 MB/s to well over
// 100.
@ chacha20_xor ( Vec u ) key i counter ( Vec u ) nonce ( Vec u ) data → ( Vec u ) {
    ^ ( chacha20_xor_range key counter nonce data 0 ( vec_len [u] data ) )
}

// The same, over the `n` bytes of `data` starting at `doff`, so a caller
// that holds its plaintext or ciphertext INSIDE a larger buffer does not
// have to slice a copy out first just to name it. An AEAD record arrives
// as ciphertext‖tag in one Vec, and every 16 KB of a TLS transfer used
// to be copied out of that buffer byte by bounds-checked byte before
// this kernel would look at it.
//
// A range not inside `data` (a negative `doff` or `n`, or `n` past
// `vec_len data - doff`) gives an empty Vec: one check a call, not a
// block.
// ── The vector kernel ────────────────────────────────────────────────
//
// One double round of ChaCha20 over four `v128` registers, in the layout
// the algorithm was designed for:
//
//     a = x0  x1  x2  x3        (the constants)
//     b = x4  x5  x6  x7        (key, low half)
//     c = x8  x9  x10 x11       (key, high half)
//     d = x12 x13 x14 x15       (counter and nonce)
//
// A column round is then FOUR quarter-rounds at once — `a += b; d ^= a;
// d <<<= 16` is one instruction per line, not four — and the diagonal
// round is the same four lines with b, c and d rotated by one, two and
// three lanes so the diagonals line up in the columns. That lane
// rotation is the whole trick, and it is why the primitives include
// exactly `rotlanes1/2/3`.
//
// Against the scalar path below: a double round is 8 quarter-rounds,
// each 4 adds, 4 xors and 4 rotates, and a rotate is a shift pair and an
// or — 160 scalar operations. Here it is 16 vector operations plus 6
// lane rotations, with each rotate costing a shift pair and an or as
// well. Same arithmetic, a quarter of the instructions.
//
// `dst` receives 64 keystream bytes. The state words go to memory
// little-endian, which is ChaCha20's serialisation — hence the
// endianness gate on the caller.
@ __chacha20_block_v128 v128 s0 v128 s1 v128 s2 v128 s3 * u dst → v {
    : ~ v128 a s0
    : ~ v128 b s1
    : ~ v128 c s2
    : ~ v128 d s3
    : ~ i r 0
    ~ < r 10 {
        // column round
        = a ( nurl_v128_add32 a b )
        = d ( nurl_v128_rotl32 ( nurl_v128_xor d a ) 16 )
        = c ( nurl_v128_add32 c d )
        = b ( nurl_v128_rotl32 ( nurl_v128_xor b c ) 12 )
        = a ( nurl_v128_add32 a b )
        = d ( nurl_v128_rotl32 ( nurl_v128_xor d a ) 8 )
        = c ( nurl_v128_add32 c d )
        = b ( nurl_v128_rotl32 ( nurl_v128_xor b c ) 7 )
        // diagonalise: the four diagonals become the four columns
        = b ( nurl_v128_rotlanes1 b )
        = c ( nurl_v128_rotlanes2 c )
        = d ( nurl_v128_rotlanes3 d )
        // diagonal round
        = a ( nurl_v128_add32 a b )
        = d ( nurl_v128_rotl32 ( nurl_v128_xor d a ) 16 )
        = c ( nurl_v128_add32 c d )
        = b ( nurl_v128_rotl32 ( nurl_v128_xor b c ) 12 )
        = a ( nurl_v128_add32 a b )
        = d ( nurl_v128_rotl32 ( nurl_v128_xor d a ) 8 )
        = c ( nurl_v128_add32 c d )
        = b ( nurl_v128_rotl32 ( nurl_v128_xor b c ) 7 )
        // undiagonalise
        = b ( nurl_v128_rotlanes3 b )
        = c ( nurl_v128_rotlanes2 c )
        = d ( nurl_v128_rotlanes1 d )
        = r + r 1
    }
    ( nurl_v128_st # s + # i dst 0 ( nurl_v128_add32 a s0 ) )
    ( nurl_v128_st # s + # i dst 16 ( nurl_v128_add32 b s1 ) )
    ( nurl_v128_st # s + # i dst 32 ( nurl_v128_add32 c s2 ) )
    ( nurl_v128_st # s + # i dst 48 ( nurl_v128_add32 d s3 ) )
}

// Two blocks at once — and the reason the vector kernel is worth having.
//
// A single ChaCha20 block is a chain: `a += b` then `d ^= a` then
// `d <<<= 16` then `c += d`, each step waiting on the one before. Four
// vector registers hold the whole state, so there is nothing else for
// the machine to issue while it waits. Measured, the one-block kernel
// retires 1.5 instructions per cycle against the scalar path's 4.2 —
// the scalar code has four independent quarter-rounds to interleave and
// runs at the issue limit, so a quarter of the instructions bought only
// a twentieth of the time.
//
// Two independent blocks, interleaved instruction by instruction below,
// give the pipeline a second chain to work on. Eight live state
// registers plus eight originals is exactly the sixteen an SSE2 or NEON
// register file has, so this is as wide as the 128-bit kernel can go
// without spilling.
//
// `dst` receives 128 keystream bytes: block `s3a` then block `s3b`.
@ __chacha20_block2_v128 v128 s0 v128 s1 v128 s2 v128 s3a v128 s3b * u dst → v {
    : ~ v128 a0 s0
    : ~ v128 b0 s1
    : ~ v128 c0 s2
    : ~ v128 d0 s3a
    : ~ v128 a1 s0
    : ~ v128 b1 s1
    : ~ v128 c1 s2
    : ~ v128 d1 s3b
    : ~ i r 0
    ~ < r 10 {
        = a0 ( nurl_v128_add32 a0 b0 )
        = a1 ( nurl_v128_add32 a1 b1 )
        = d0 ( nurl_v128_rotl32 ( nurl_v128_xor d0 a0 ) 16 )
        = d1 ( nurl_v128_rotl32 ( nurl_v128_xor d1 a1 ) 16 )
        = c0 ( nurl_v128_add32 c0 d0 )
        = c1 ( nurl_v128_add32 c1 d1 )
        = b0 ( nurl_v128_rotl32 ( nurl_v128_xor b0 c0 ) 12 )
        = b1 ( nurl_v128_rotl32 ( nurl_v128_xor b1 c1 ) 12 )
        = a0 ( nurl_v128_add32 a0 b0 )
        = a1 ( nurl_v128_add32 a1 b1 )
        = d0 ( nurl_v128_rotl32 ( nurl_v128_xor d0 a0 ) 8 )
        = d1 ( nurl_v128_rotl32 ( nurl_v128_xor d1 a1 ) 8 )
        = c0 ( nurl_v128_add32 c0 d0 )
        = c1 ( nurl_v128_add32 c1 d1 )
        = b0 ( nurl_v128_rotl32 ( nurl_v128_xor b0 c0 ) 7 )
        = b1 ( nurl_v128_rotl32 ( nurl_v128_xor b1 c1 ) 7 )
        // diagonalise both blocks: the four diagonals become the columns
        = b0 ( nurl_v128_rotlanes1 b0 )
        = b1 ( nurl_v128_rotlanes1 b1 )
        = c0 ( nurl_v128_rotlanes2 c0 )
        = c1 ( nurl_v128_rotlanes2 c1 )
        = d0 ( nurl_v128_rotlanes3 d0 )
        = d1 ( nurl_v128_rotlanes3 d1 )
        = a0 ( nurl_v128_add32 a0 b0 )
        = a1 ( nurl_v128_add32 a1 b1 )
        = d0 ( nurl_v128_rotl32 ( nurl_v128_xor d0 a0 ) 16 )
        = d1 ( nurl_v128_rotl32 ( nurl_v128_xor d1 a1 ) 16 )
        = c0 ( nurl_v128_add32 c0 d0 )
        = c1 ( nurl_v128_add32 c1 d1 )
        = b0 ( nurl_v128_rotl32 ( nurl_v128_xor b0 c0 ) 12 )
        = b1 ( nurl_v128_rotl32 ( nurl_v128_xor b1 c1 ) 12 )
        = a0 ( nurl_v128_add32 a0 b0 )
        = a1 ( nurl_v128_add32 a1 b1 )
        = d0 ( nurl_v128_rotl32 ( nurl_v128_xor d0 a0 ) 8 )
        = d1 ( nurl_v128_rotl32 ( nurl_v128_xor d1 a1 ) 8 )
        = c0 ( nurl_v128_add32 c0 d0 )
        = c1 ( nurl_v128_add32 c1 d1 )
        = b0 ( nurl_v128_rotl32 ( nurl_v128_xor b0 c0 ) 7 )
        = b1 ( nurl_v128_rotl32 ( nurl_v128_xor b1 c1 ) 7 )
        // undiagonalise
        = b0 ( nurl_v128_rotlanes3 b0 )
        = b1 ( nurl_v128_rotlanes3 b1 )
        = c0 ( nurl_v128_rotlanes2 c0 )
        = c1 ( nurl_v128_rotlanes2 c1 )
        = d0 ( nurl_v128_rotlanes1 d0 )
        = d1 ( nurl_v128_rotlanes1 d1 )
        = r + r 1
    }
    ( nurl_v128_st # s + # i dst 0 ( nurl_v128_add32 a0 s0 ) )
    ( nurl_v128_st # s + # i dst 16 ( nurl_v128_add32 b0 s1 ) )
    ( nurl_v128_st # s + # i dst 32 ( nurl_v128_add32 c0 s2 ) )
    ( nurl_v128_st # s + # i dst 48 ( nurl_v128_add32 d0 s3a ) )
    ( nurl_v128_st # s + # i dst 64 ( nurl_v128_add32 a1 s0 ) )
    ( nurl_v128_st # s + # i dst 80 ( nurl_v128_add32 b1 s1 ) )
    ( nurl_v128_st # s + # i dst 96 ( nurl_v128_add32 c1 s2 ) )
    ( nurl_v128_st # s + # i dst 112 ( nurl_v128_add32 d1 s3b ) )
}

& `c` @ nurl_simd128_native → i

// Four blocks at once, one block per lane — the layout the fast ChaCha20s
// all use. Vector x_w holds state word w of blocks ctr..ctr+3, so a
// quarter-round is eight plain vector operations on four whole vectors
// and the diagonal round needs no lane rotation at all: the kernels above
// spend a third of their work turning diagonals into columns and back, and
// stall on one block's chain where this one has four in flight. The words
// come back to block order through 4×4 transposes (__cc_xor4) on the way
// out.
inline @ __cc_qr4 inout v128 a inout v128 b inout v128 c inout v128 d → v {
    = a ( nurl_v128_add32 a b )
    = d ( nurl_v128_rotl32 ( nurl_v128_xor d a ) 16 )
    = c ( nurl_v128_add32 c d )
    = b ( nurl_v128_rotl32 ( nurl_v128_xor b c ) 12 )
    = a ( nurl_v128_add32 a b )
    = d ( nurl_v128_rotl32 ( nurl_v128_xor d a ) 8 )
    = c ( nurl_v128_add32 c d )
    = b ( nurl_v128_rotl32 ( nurl_v128_xor b c ) 7 )
}

// Words w..w+3 of the four blocks (x0..x3: word w+k of block j in lane j),
// transposed so each block's four words are one vector, XORed with the
// input at block j's offset 64·j + 4·w and stored to the output.
inline @ __cc_xor4 v128 x0 v128 x1 v128 x2 v128 x3 * u src * u dst i w → v {
    : v128 t0 ( nurl_v128_unpacklo32 x0 x1 )
    : v128 t1 ( nurl_v128_unpacklo32 x2 x3 )
    : v128 t2 ( nurl_v128_unpackhi32 x0 x1 )
    : v128 t3 ( nurl_v128_unpackhi32 x2 x3 )
    : i o * w 4
    ( nurl_v128_st # s + # i dst o ( nurl_v128_xor ( nurl_v128_ld # s + # i src o ) ( nurl_v128_unpacklo64 t0 t1 ) ) )
    ( nurl_v128_st # s + # i dst + o 64 ( nurl_v128_xor ( nurl_v128_ld # s + # i src + o 64 ) ( nurl_v128_unpackhi64 t0 t1 ) ) )
    ( nurl_v128_st # s + # i dst + o 128 ( nurl_v128_xor ( nurl_v128_ld # s + # i src + o 128 ) ( nurl_v128_unpacklo64 t2 t3 ) ) )
    ( nurl_v128_st # s + # i dst + o 192 ( nurl_v128_xor ( nurl_v128_ld # s + # i src + o 192 ) ( nurl_v128_unpackhi64 t2 t3 ) ) )
}

// dst[0..256) = src[0..256) XOR the keystream of blocks ctr..ctr+3, the key
// and nonce given as their little-endian words.
inline @ __chacha20_xor4_v128 i k0 i k1 i k2 i k3 i k4 i k5 i k6 i k7 i ctr i n0 i n1 i n2 * u src * u dst → v {
    : v128 ct ( nurl_v128_set32 ctr + ctr 1 + ctr 2 + ctr 3 )
    : ~ v128 x0 ( nurl_v128_bcast32 1634760805 )
    : ~ v128 x1 ( nurl_v128_bcast32 857760878 )
    : ~ v128 x2 ( nurl_v128_bcast32 2036477234 )
    : ~ v128 x3 ( nurl_v128_bcast32 1797285236 )
    : ~ v128 x4 ( nurl_v128_bcast32 k0 )
    : ~ v128 x5 ( nurl_v128_bcast32 k1 )
    : ~ v128 x6 ( nurl_v128_bcast32 k2 )
    : ~ v128 x7 ( nurl_v128_bcast32 k3 )
    : ~ v128 x8 ( nurl_v128_bcast32 k4 )
    : ~ v128 x9 ( nurl_v128_bcast32 k5 )
    : ~ v128 x10 ( nurl_v128_bcast32 k6 )
    : ~ v128 x11 ( nurl_v128_bcast32 k7 )
    : ~ v128 x12 ct
    : ~ v128 x13 ( nurl_v128_bcast32 n0 )
    : ~ v128 x14 ( nurl_v128_bcast32 n1 )
    : ~ v128 x15 ( nurl_v128_bcast32 n2 )
    : ~ i r 0
    ~ < r 10 {
        ( __cc_qr4 x0 x4 x8 x12 )
        ( __cc_qr4 x1 x5 x9 x13 )
        ( __cc_qr4 x2 x6 x10 x14 )
        ( __cc_qr4 x3 x7 x11 x15 )
        ( __cc_qr4 x0 x5 x10 x15 )
        ( __cc_qr4 x1 x6 x11 x12 )
        ( __cc_qr4 x2 x7 x8 x13 )
        ( __cc_qr4 x3 x4 x9 x14 )
        = r + r 1
    }
    ( __cc_xor4 ( nurl_v128_add32 x0 ( nurl_v128_bcast32 1634760805 ) ) ( nurl_v128_add32 x1 ( nurl_v128_bcast32 857760878 ) ) ( nurl_v128_add32 x2 ( nurl_v128_bcast32 2036477234 ) ) ( nurl_v128_add32 x3 ( nurl_v128_bcast32 1797285236 ) ) src dst 0 )
    ( __cc_xor4 ( nurl_v128_add32 x4 ( nurl_v128_bcast32 k0 ) ) ( nurl_v128_add32 x5 ( nurl_v128_bcast32 k1 ) ) ( nurl_v128_add32 x6 ( nurl_v128_bcast32 k2 ) ) ( nurl_v128_add32 x7 ( nurl_v128_bcast32 k3 ) ) src dst 4 )
    ( __cc_xor4 ( nurl_v128_add32 x8 ( nurl_v128_bcast32 k4 ) ) ( nurl_v128_add32 x9 ( nurl_v128_bcast32 k5 ) ) ( nurl_v128_add32 x10 ( nurl_v128_bcast32 k6 ) ) ( nurl_v128_add32 x11 ( nurl_v128_bcast32 k7 ) ) src dst 8 )
    ( __cc_xor4 ( nurl_v128_add32 x12 ct ) ( nurl_v128_add32 x13 ( nurl_v128_bcast32 n0 ) ) ( nurl_v128_add32 x14 ( nurl_v128_bcast32 n1 ) ) ( nurl_v128_add32 x15 ( nurl_v128_bcast32 n2 ) ) src dst 12 )
}

// Eight blocks at once over v256 — the same one-block-per-lane layout as
// __chacha20_xor4_v128, twice as wide. Worth it only with 256-bit
// registers (on a CPU without AVX2 every v256 operation is two SSE2 ones
// and sixteen live state vectors no longer fit), so chacha20_xor_range
// runs it only where nurl_cpu_x86_v3 says the AVX2 clone is the one
// running.
inline @ __cc_qr8 inout v256 a inout v256 b inout v256 c inout v256 d → v {
    = a ( nurl_v256_add32 a b )
    = d ( nurl_v256_rotl32 ( nurl_v256_xor d a ) 16 )
    = c ( nurl_v256_add32 c d )
    = b ( nurl_v256_rotl32 ( nurl_v256_xor b c ) 12 )
    = a ( nurl_v256_add32 a b )
    = d ( nurl_v256_rotl32 ( nurl_v256_xor d a ) 8 )
    = c ( nurl_v256_add32 c d )
    = b ( nurl_v256_rotl32 ( nurl_v256_xor b c ) 7 )
}

// x0..x3 hold words w..w+3 of the eight blocks (block j in lane j); the
// in-half 4x4 transpose leaves block j's four words in half j/4 of output
// j mod 4.
inline @ __cc_tr8 inout v256 x0 inout v256 x1 inout v256 x2 inout v256 x3 → v {
    : v256 t0 ( nurl_v256_unpacklo32 x0 x1 )
    : v256 t1 ( nurl_v256_unpacklo32 x2 x3 )
    : v256 t2 ( nurl_v256_unpackhi32 x0 x1 )
    : v256 t3 ( nurl_v256_unpackhi32 x2 x3 )
    = x0 ( nurl_v256_unpacklo64 t0 t1 )
    = x1 ( nurl_v256_unpackhi64 t0 t1 )
    = x2 ( nurl_v256_unpacklo64 t2 t3 )
    = x3 ( nurl_v256_unpackhi64 t2 t3 )
}

// dst[at .. at+32) = src[at .. at+32) XOR v.
inline @ __cc_x32 * u src * u dst i at v256 v → v {
    ( nurl_v256_st # s + # i dst at ( nurl_v256_xor ( nurl_v256_ld # s + # i src at ) v ) )
}

// dst[0..512) = src[0..512) XOR the keystream of blocks ctr..ctr+7.
inline @ __chacha20_xor8_v256 i k0 i k1 i k2 i k3 i k4 i k5 i k6 i k7 i ctr i n0 i n1 i n2 * u src * u dst → v {
    // 0..7 in the eight 32-bit lanes (two per 64-bit lane, low first)
    : v256 ct ( nurl_v256_add32 ( nurl_v256_bcast32 ctr ) ( nurl_v256_set64 4294967296 12884901890 21474836484 30064771078 ) )
    : ~ v256 x0 ( nurl_v256_bcast32 1634760805 )
    : ~ v256 x1 ( nurl_v256_bcast32 857760878 )
    : ~ v256 x2 ( nurl_v256_bcast32 2036477234 )
    : ~ v256 x3 ( nurl_v256_bcast32 1797285236 )
    : ~ v256 x4 ( nurl_v256_bcast32 k0 )
    : ~ v256 x5 ( nurl_v256_bcast32 k1 )
    : ~ v256 x6 ( nurl_v256_bcast32 k2 )
    : ~ v256 x7 ( nurl_v256_bcast32 k3 )
    : ~ v256 x8 ( nurl_v256_bcast32 k4 )
    : ~ v256 x9 ( nurl_v256_bcast32 k5 )
    : ~ v256 x10 ( nurl_v256_bcast32 k6 )
    : ~ v256 x11 ( nurl_v256_bcast32 k7 )
    : ~ v256 x12 ct
    : ~ v256 x13 ( nurl_v256_bcast32 n0 )
    : ~ v256 x14 ( nurl_v256_bcast32 n1 )
    : ~ v256 x15 ( nurl_v256_bcast32 n2 )
    : ~ i r 0
    ~ < r 10 {
        ( __cc_qr8 x0 x4 x8 x12 )
        ( __cc_qr8 x1 x5 x9 x13 )
        ( __cc_qr8 x2 x6 x10 x14 )
        ( __cc_qr8 x3 x7 x11 x15 )
        ( __cc_qr8 x0 x5 x10 x15 )
        ( __cc_qr8 x1 x6 x11 x12 )
        ( __cc_qr8 x2 x7 x8 x13 )
        ( __cc_qr8 x3 x4 x9 x14 )
        = r + r 1
    }
    = x0 ( nurl_v256_add32 x0 ( nurl_v256_bcast32 1634760805 ) )
    = x1 ( nurl_v256_add32 x1 ( nurl_v256_bcast32 857760878 ) )
    = x2 ( nurl_v256_add32 x2 ( nurl_v256_bcast32 2036477234 ) )
    = x3 ( nurl_v256_add32 x3 ( nurl_v256_bcast32 1797285236 ) )
    = x4 ( nurl_v256_add32 x4 ( nurl_v256_bcast32 k0 ) )
    = x5 ( nurl_v256_add32 x5 ( nurl_v256_bcast32 k1 ) )
    = x6 ( nurl_v256_add32 x6 ( nurl_v256_bcast32 k2 ) )
    = x7 ( nurl_v256_add32 x7 ( nurl_v256_bcast32 k3 ) )
    = x8 ( nurl_v256_add32 x8 ( nurl_v256_bcast32 k4 ) )
    = x9 ( nurl_v256_add32 x9 ( nurl_v256_bcast32 k5 ) )
    = x10 ( nurl_v256_add32 x10 ( nurl_v256_bcast32 k6 ) )
    = x11 ( nurl_v256_add32 x11 ( nurl_v256_bcast32 k7 ) )
    = x12 ( nurl_v256_add32 x12 ct )
    = x13 ( nurl_v256_add32 x13 ( nurl_v256_bcast32 n0 ) )
    = x14 ( nurl_v256_add32 x14 ( nurl_v256_bcast32 n1 ) )
    = x15 ( nurl_v256_add32 x15 ( nurl_v256_bcast32 n2 ) )
    ( __cc_tr8 x0 x1 x2 x3 )
    ( __cc_tr8 x4 x5 x6 x7 )
    ( __cc_tr8 x8 x9 x10 x11 )
    ( __cc_tr8 x12 x13 x14 x15 )
    // block j (j < 4): words 0-7 = low halves of x_j and x_{4+j}, words 8-15
    // = low halves of x_{8+j} and x_{12+j}; block j+4 the high halves
    ( __cc_x32 src dst 0 ( nurl_v256_permlo128 x0 x4 ) )
    ( __cc_x32 src dst 32 ( nurl_v256_permlo128 x8 x12 ) )
    ( __cc_x32 src dst 256 ( nurl_v256_permhi128 x0 x4 ) )
    ( __cc_x32 src dst 288 ( nurl_v256_permhi128 x8 x12 ) )
    ( __cc_x32 src dst 64 ( nurl_v256_permlo128 x1 x5 ) )
    ( __cc_x32 src dst 96 ( nurl_v256_permlo128 x9 x13 ) )
    ( __cc_x32 src dst 320 ( nurl_v256_permhi128 x1 x5 ) )
    ( __cc_x32 src dst 352 ( nurl_v256_permhi128 x9 x13 ) )
    ( __cc_x32 src dst 128 ( nurl_v256_permlo128 x2 x6 ) )
    ( __cc_x32 src dst 160 ( nurl_v256_permlo128 x10 x14 ) )
    ( __cc_x32 src dst 384 ( nurl_v256_permhi128 x2 x6 ) )
    ( __cc_x32 src dst 416 ( nurl_v256_permhi128 x10 x14 ) )
    ( __cc_x32 src dst 192 ( nurl_v256_permlo128 x3 x7 ) )
    ( __cc_x32 src dst 224 ( nurl_v256_permlo128 x11 x15 ) )
    ( __cc_x32 src dst 448 ( nurl_v256_permhi128 x3 x7 ) )
    ( __cc_x32 src dst 480 ( nurl_v256_permhi128 x11 x15 ) )
}

// The wide passes over n bytes from dp to op, block counter ctr: eight
// blocks a pass over v256 lanes in the x86-64-v3 clone, four over v128
// lanes after that. Returns the bytes done — a multiple of 256, the rest
// left to the caller's narrower kernels. A function of its own, called
// only where v128 is native: a wasm module (whose v128 scalarises) carries
// it but its JIT never compiles it, and the caller stays small enough for
// a register allocator to keep its two-block loop in registers.
simd @ __chacha20_xor_wide ( Vec u ) key i ctr0 i nn0 i nn1 i nn2 * u dp * u op i n → i {
    : i k0 ( __ld32 key 0 )
    : i k1 ( __ld32 key 4 )
    : i k2 ( __ld32 key 8 )
    : i k3 ( __ld32 key 12 )
    : i k4 ( __ld32 key 16 )
    : i k5 ( __ld32 key 20 )
    : i k6 ( __ld32 key 24 )
    : i k7 ( __ld32 key 28 )
    : ~ i ctr ctr0
    : ~ i off 0
    ? & >= n 512 != 0 # i ( nurl_cpu_x86_v3 ) {
        ~ <= + off 512 n {
            ( __chacha20_xor8_v256 k0 k1 k2 k3 k4 k5 k6 k7 ctr nn0 nn1 nn2 # *u + # i dp off # *u + # i op off )
            = ctr + ctr 8
            = off + off 512
        }
    } {}
    ~ <= + off 256 n {
        ( __chacha20_xor4_v128 k0 k1 k2 k3 k4 k5 k6 k7 ctr nn0 nn1 nn2 # *u + # i dp off # *u + # i op off )
        = ctr + ctr 4
        = off + off 256
    }
    ^ off
}

// out[0..n) = data[doff..doff+n) XOR ChaCha20(key, counter, nonce).
//
// Dispatches to the vector kernels on a little-endian host — every
// platform NURL targets in practice — and to the scalar reference
// otherwise: the wide passes where vectors are native (__chacha20_xor_wide),
// then two blocks a pass, then one. The vector paths XOR whole blocks
// straight from the input pointer to the output pointer; only a final
// partial block goes through a 64-byte keystream scratch.
@ chacha20_xor_range ( Vec u ) key i counter ( Vec u ) nonce ( Vec u ) data i doff i n → ( Vec u ) {
    ? | | < doff 0 < n 0 > n - ( vec_len [u] data ) doff { ^ ( vec_new [u] ) } {}
    ? == 0 ( __le_words )
    { ^ ( _chacha20_xor_range_scalar key counter nonce data doff n ) } {}
    : ( Vec u ) out ( __xor_out n 128 )
    ? == n 0 { ^ out } {}
    : *u op ( vec_data [u] out )
    ( __chacha20_xor_ptr key counter ( __ld32 nonce 0 ) ( __ld32 nonce 4 ) ( __ld32 nonce 8 ) # *u + # i ( vec_data [u] data ) doff op n # *u + # i op ( __xor_scratch_at n ) )
    ^ out
}

// The vector kernels on raw memory: `n` bytes from `dp` to `op` XORed
// with ChaCha20(key, counter, nonce words nn0..nn2). `op` may be `dp` —
// every block is read before its output is written — so a record can be
// encrypted where it lies. `ks` is 128 bytes of scratch overlapping
// neither. Little-endian hosts only (the caller asks __le_words).
unsafe @ __chacha20_xor_ptr ( Vec u ) key i counter i nn0 i nn1 i nn2 * u dp * u op i n * u ks → v {
    : v128 s0 ( nurl_v128_set32 1634760805 857760878 2036477234 1797285236 )
    : v128 s1 ( nurl_v128_set32 ( __ld32 key 0 ) ( __ld32 key 4 ) ( __ld32 key 8 ) ( __ld32 key 12 ) )
    : v128 s2 ( nurl_v128_set32 ( __ld32 key 16 ) ( __ld32 key 20 ) ( __ld32 key 24 ) ( __ld32 key 28 ) )
    : ~ i ctr counter
    : ~ i off 0
    // The wide passes while at least 256 bytes remain, then two blocks a
    // pass while 128 do; the tail falls through to the one-block kernel
    // and then to a byte loop.
    ? & >= n 256 != 0 ( nurl_simd128_native ) {
        = off ( __chacha20_xor_wide key ctr nn0 nn1 nn2 dp op n )
        = ctr + ctr >> off 6
    } {}
    ~ <= + off 128 n {
        ( __chacha20_block2_v128 s0 s1 s2
        ( nurl_v128_set32 ctr nn0 nn1 nn2 )
        ( nurl_v128_set32 + ctr 1 nn0 nn1 nn2 ) ks )
        : ~ i v 0
        ~ < v 128 {
            ( nurl_v128_st # s + # i op + off v
            ( nurl_v128_xor ( nurl_v128_ld # s + # i dp + off v ) ( nurl_v128_ld # s + # i ks v ) ) )
            = v + v 16
        }
        = ctr + ctr 2
        = off + off 128
    }
    ~ < off n {
        : v128 s3 ( nurl_v128_set32 ctr nn0 nn1 nn2 )
        : i left - n off
        ? >= left 64 {
            // Whole block: keystream never touches memory as a block —
            // it is XORed into place one vector at a time.
            ( __chacha20_block_v128 s0 s1 s2 s3 ks )
            ( nurl_v128_st # s + # i op + off 0
            ( nurl_v128_xor ( nurl_v128_ld # s + # i dp + off 0 ) ( nurl_v128_ld # s + # i ks 0 ) ) )
            ( nurl_v128_st # s + # i op + off 16
            ( nurl_v128_xor ( nurl_v128_ld # s + # i dp + off 16 ) ( nurl_v128_ld # s + # i ks 16 ) ) )
            ( nurl_v128_st # s + # i op + off 32
            ( nurl_v128_xor ( nurl_v128_ld # s + # i dp + off 32 ) ( nurl_v128_ld # s + # i ks 32 ) ) )
            ( nurl_v128_st # s + # i op + off 48
            ( nurl_v128_xor ( nurl_v128_ld # s + # i dp + off 48 ) ( nurl_v128_ld # s + # i ks 48 ) ) )
        } {
            ( __chacha20_block_v128 s0 s1 s2 s3 ks )
            : ~ i q 0
            ~ < q left {
                = . op + off q # u ^^ & 255 # i . dp + off q & 255 # i . ks q
                = q + q 1
            }
        }
        = ctr + ctr 1
        = off + off 64
    }
}

// Scalar keystream path — the reference implementation, and what runs
// on a big-endian target where a vector store would lay the state's
// 32-bit words down in the wrong byte order. See chacha20_xor_range
// below for the vector path that handles every little-endian host.
// requires: 0 ≤ doff, 0 ≤ n and n ≤ vec_len data − doff (chacha20_xor_range
// checks it; the range is read through `vec_data` unchecked).
raw @ _chacha20_xor_range_scalar ( Vec u ) key i counter ( Vec u ) nonce ( Vec u ) data i doff i n → ( Vec u ) {
    : ( Vec u ) out ( __xor_out n 64 )
    ? == n 0 { ^ out } {}
    : *u dp # *u + # i ( vec_data [u] data ) doff
    : *u op ( vec_data [u] out )
    : u32 k0 # u32 ( __ld32 key 0 )
    : u32 k1 # u32 ( __ld32 key 4 )
    : u32 k2 # u32 ( __ld32 key 8 )
    : u32 k3 # u32 ( __ld32 key 12 )
    : u32 k4 # u32 ( __ld32 key 16 )
    : u32 k5 # u32 ( __ld32 key 20 )
    : u32 k6 # u32 ( __ld32 key 24 )
    : u32 k7 # u32 ( __ld32 key 28 )
    : u32 n0 # u32 ( __ld32 nonce 0 )
    : u32 n1 # u32 ( __ld32 nonce 4 )
    : u32 n2 # u32 ( __ld32 nonce 8 )
    // Whole-block XOR through 8-byte loads and stores when both buffers
    // are 8-byte aligned — a Vec's storage comes from malloc, so they
    // are unless a caller hands in an unaligned `doff`. Eight loads,
    // eight XORs and eight stores a block, against sixty-four of each
    // plus their shifts and masks on the byte path below, which stays as
    // the fallback for the unaligned and big-endian cases.
    : i wordio & ( __le_words ) ? == 0 | & # i dp 7 & # i op 7 1 0
    : *u ks # *u + # i op ( __xor_scratch_at n )
    : ~ i ctr counter
    : ~ i off 0
    ~ < off n {
        : ~ u32 x0 1634760805
        : ~ u32 x1 857760878
        : ~ u32 x2 2036477234
        : ~ u32 x3 1797285236
        : ~ u32 x4 k0
        : ~ u32 x5 k1
        : ~ u32 x6 k2
        : ~ u32 x7 k3
        : ~ u32 x8 k4
        : ~ u32 x9 k5
        : ~ u32 x10 k6
        : ~ u32 x11 k7
        : ~ u32 x12 # u32 ctr
        : ~ u32 x13 n0
        : ~ u32 x14 n1
        : ~ u32 x15 n2
        : ~ i rr 0
        ~ < rr 10 {
            = x0 + x0 x4
            = x12 ^^ x12 x0
            = x12 | << x12 16 >> x12 16
            = x8 + x8 x12
            = x4 ^^ x4 x8
            = x4 | << x4 12 >> x4 20
            = x0 + x0 x4
            = x12 ^^ x12 x0
            = x12 | << x12 8 >> x12 24
            = x8 + x8 x12
            = x4 ^^ x4 x8
            = x4 | << x4 7 >> x4 25
            = x1 + x1 x5
            = x13 ^^ x13 x1
            = x13 | << x13 16 >> x13 16
            = x9 + x9 x13
            = x5 ^^ x5 x9
            = x5 | << x5 12 >> x5 20
            = x1 + x1 x5
            = x13 ^^ x13 x1
            = x13 | << x13 8 >> x13 24
            = x9 + x9 x13
            = x5 ^^ x5 x9
            = x5 | << x5 7 >> x5 25
            = x2 + x2 x6
            = x14 ^^ x14 x2
            = x14 | << x14 16 >> x14 16
            = x10 + x10 x14
            = x6 ^^ x6 x10
            = x6 | << x6 12 >> x6 20
            = x2 + x2 x6
            = x14 ^^ x14 x2
            = x14 | << x14 8 >> x14 24
            = x10 + x10 x14
            = x6 ^^ x6 x10
            = x6 | << x6 7 >> x6 25
            = x3 + x3 x7
            = x15 ^^ x15 x3
            = x15 | << x15 16 >> x15 16
            = x11 + x11 x15
            = x7 ^^ x7 x11
            = x7 | << x7 12 >> x7 20
            = x3 + x3 x7
            = x15 ^^ x15 x3
            = x15 | << x15 8 >> x15 24
            = x11 + x11 x15
            = x7 ^^ x7 x11
            = x7 | << x7 7 >> x7 25
            = x0 + x0 x5
            = x15 ^^ x15 x0
            = x15 | << x15 16 >> x15 16
            = x10 + x10 x15
            = x5 ^^ x5 x10
            = x5 | << x5 12 >> x5 20
            = x0 + x0 x5
            = x15 ^^ x15 x0
            = x15 | << x15 8 >> x15 24
            = x10 + x10 x15
            = x5 ^^ x5 x10
            = x5 | << x5 7 >> x5 25
            = x1 + x1 x6
            = x12 ^^ x12 x1
            = x12 | << x12 16 >> x12 16
            = x11 + x11 x12
            = x6 ^^ x6 x11
            = x6 | << x6 12 >> x6 20
            = x1 + x1 x6
            = x12 ^^ x12 x1
            = x12 | << x12 8 >> x12 24
            = x11 + x11 x12
            = x6 ^^ x6 x11
            = x6 | << x6 7 >> x6 25
            = x2 + x2 x7
            = x13 ^^ x13 x2
            = x13 | << x13 16 >> x13 16
            = x8 + x8 x13
            = x7 ^^ x7 x8
            = x7 | << x7 12 >> x7 20
            = x2 + x2 x7
            = x13 ^^ x13 x2
            = x13 | << x13 8 >> x13 24
            = x8 + x8 x13
            = x7 ^^ x7 x8
            = x7 | << x7 7 >> x7 25
            = x3 + x3 x4
            = x14 ^^ x14 x3
            = x14 | << x14 16 >> x14 16
            = x9 + x9 x14
            = x4 ^^ x4 x9
            = x4 | << x4 12 >> x4 20
            = x3 + x3 x4
            = x14 ^^ x14 x3
            = x14 | << x14 8 >> x14 24
            = x9 + x9 x14
            = x4 ^^ x4 x9
            = x4 | << x4 7 >> x4 25
            = rr + rr 1
        }
        = x0 + x0 1634760805
        = x1 + x1 857760878
        = x2 + x2 2036477234
        = x3 + x3 1797285236
        = x4 + x4 k0
        = x5 + x5 k1
        = x6 + x6 k2
        = x7 + x7 k3
        = x8 + x8 k4
        = x9 + x9 k5
        = x10 + x10 k6
        = x11 + x11 k7
        = x12 + x12 # u32 ctr
        = x13 + x13 n0
        = x14 + x14 n1
        = x15 + x15 n2
        ? & == 1 wordio >= - n off 64 {
            // Eight machine words: the state pairs up low-word-first,
            // which is the same byte order the byte path spells out.
            : i w8 >> off 3
            ( nurl_poke # s op w8 ^^ ( nurl_peek # s dp w8 ) | # i x0 << # i x1 32 )
            ( nurl_poke # s op + w8 1 ^^ ( nurl_peek # s dp + w8 1 ) | # i x2 << # i x3 32 )
            ( nurl_poke # s op + w8 2 ^^ ( nurl_peek # s dp + w8 2 ) | # i x4 << # i x5 32 )
            ( nurl_poke # s op + w8 3 ^^ ( nurl_peek # s dp + w8 3 ) | # i x6 << # i x7 32 )
            ( nurl_poke # s op + w8 4 ^^ ( nurl_peek # s dp + w8 4 ) | # i x8 << # i x9 32 )
            ( nurl_poke # s op + w8 5 ^^ ( nurl_peek # s dp + w8 5 ) | # i x10 << # i x11 32 )
            ( nurl_poke # s op + w8 6 ^^ ( nurl_peek # s dp + w8 6 ) | # i x12 << # i x13 32 )
            ( nurl_poke # s op + w8 7 ^^ ( nurl_peek # s dp + w8 7 ) | # i x14 << # i x15 32 )
        } {}
        // Both write the same bytes; only the width differs.
        ? & == 0 wordio >= - n off 64 {
            : i v0 # i x0
            = . op off # u ^^ # i . dp off & v0 255
            = . op + off 1 # u ^^ # i . dp + off 1 & >> v0 8 255
            = . op + off 2 # u ^^ # i . dp + off 2 & >> v0 16 255
            = . op + off 3 # u ^^ # i . dp + off 3 & >> v0 24 255
            : i v1 # i x1
            = . op + off 4 # u ^^ # i . dp + off 4 & v1 255
            = . op + off 5 # u ^^ # i . dp + off 5 & >> v1 8 255
            = . op + off 6 # u ^^ # i . dp + off 6 & >> v1 16 255
            = . op + off 7 # u ^^ # i . dp + off 7 & >> v1 24 255
            : i v2 # i x2
            = . op + off 8 # u ^^ # i . dp + off 8 & v2 255
            = . op + off 9 # u ^^ # i . dp + off 9 & >> v2 8 255
            = . op + off 10 # u ^^ # i . dp + off 10 & >> v2 16 255
            = . op + off 11 # u ^^ # i . dp + off 11 & >> v2 24 255
            : i v3 # i x3
            = . op + off 12 # u ^^ # i . dp + off 12 & v3 255
            = . op + off 13 # u ^^ # i . dp + off 13 & >> v3 8 255
            = . op + off 14 # u ^^ # i . dp + off 14 & >> v3 16 255
            = . op + off 15 # u ^^ # i . dp + off 15 & >> v3 24 255
            : i v4 # i x4
            = . op + off 16 # u ^^ # i . dp + off 16 & v4 255
            = . op + off 17 # u ^^ # i . dp + off 17 & >> v4 8 255
            = . op + off 18 # u ^^ # i . dp + off 18 & >> v4 16 255
            = . op + off 19 # u ^^ # i . dp + off 19 & >> v4 24 255
            : i v5 # i x5
            = . op + off 20 # u ^^ # i . dp + off 20 & v5 255
            = . op + off 21 # u ^^ # i . dp + off 21 & >> v5 8 255
            = . op + off 22 # u ^^ # i . dp + off 22 & >> v5 16 255
            = . op + off 23 # u ^^ # i . dp + off 23 & >> v5 24 255
            : i v6 # i x6
            = . op + off 24 # u ^^ # i . dp + off 24 & v6 255
            = . op + off 25 # u ^^ # i . dp + off 25 & >> v6 8 255
            = . op + off 26 # u ^^ # i . dp + off 26 & >> v6 16 255
            = . op + off 27 # u ^^ # i . dp + off 27 & >> v6 24 255
            : i v7 # i x7
            = . op + off 28 # u ^^ # i . dp + off 28 & v7 255
            = . op + off 29 # u ^^ # i . dp + off 29 & >> v7 8 255
            = . op + off 30 # u ^^ # i . dp + off 30 & >> v7 16 255
            = . op + off 31 # u ^^ # i . dp + off 31 & >> v7 24 255
            : i v8 # i x8
            = . op + off 32 # u ^^ # i . dp + off 32 & v8 255
            = . op + off 33 # u ^^ # i . dp + off 33 & >> v8 8 255
            = . op + off 34 # u ^^ # i . dp + off 34 & >> v8 16 255
            = . op + off 35 # u ^^ # i . dp + off 35 & >> v8 24 255
            : i v9 # i x9
            = . op + off 36 # u ^^ # i . dp + off 36 & v9 255
            = . op + off 37 # u ^^ # i . dp + off 37 & >> v9 8 255
            = . op + off 38 # u ^^ # i . dp + off 38 & >> v9 16 255
            = . op + off 39 # u ^^ # i . dp + off 39 & >> v9 24 255
            : i v10 # i x10
            = . op + off 40 # u ^^ # i . dp + off 40 & v10 255
            = . op + off 41 # u ^^ # i . dp + off 41 & >> v10 8 255
            = . op + off 42 # u ^^ # i . dp + off 42 & >> v10 16 255
            = . op + off 43 # u ^^ # i . dp + off 43 & >> v10 24 255
            : i v11 # i x11
            = . op + off 44 # u ^^ # i . dp + off 44 & v11 255
            = . op + off 45 # u ^^ # i . dp + off 45 & >> v11 8 255
            = . op + off 46 # u ^^ # i . dp + off 46 & >> v11 16 255
            = . op + off 47 # u ^^ # i . dp + off 47 & >> v11 24 255
            : i v12 # i x12
            = . op + off 48 # u ^^ # i . dp + off 48 & v12 255
            = . op + off 49 # u ^^ # i . dp + off 49 & >> v12 8 255
            = . op + off 50 # u ^^ # i . dp + off 50 & >> v12 16 255
            = . op + off 51 # u ^^ # i . dp + off 51 & >> v12 24 255
            : i v13 # i x13
            = . op + off 52 # u ^^ # i . dp + off 52 & v13 255
            = . op + off 53 # u ^^ # i . dp + off 53 & >> v13 8 255
            = . op + off 54 # u ^^ # i . dp + off 54 & >> v13 16 255
            = . op + off 55 # u ^^ # i . dp + off 55 & >> v13 24 255
            : i v14 # i x14
            = . op + off 56 # u ^^ # i . dp + off 56 & v14 255
            = . op + off 57 # u ^^ # i . dp + off 57 & >> v14 8 255
            = . op + off 58 # u ^^ # i . dp + off 58 & >> v14 16 255
            = . op + off 59 # u ^^ # i . dp + off 59 & >> v14 24 255
            : i v15 # i x15
            = . op + off 60 # u ^^ # i . dp + off 60 & v15 255
            = . op + off 61 # u ^^ # i . dp + off 61 & >> v15 8 255
            = . op + off 62 # u ^^ # i . dp + off 62 & >> v15 16 255
            = . op + off 63 # u ^^ # i . dp + off 63 & >> v15 24 255
        } {}
        ? < - n off 64 {
            : i v0 # i x0
            = . ks 0 # u & v0 255
            = . ks 1 # u & >> v0 8 255
            = . ks 2 # u & >> v0 16 255
            = . ks 3 # u & >> v0 24 255
            : i v1 # i x1
            = . ks 4 # u & v1 255
            = . ks 5 # u & >> v1 8 255
            = . ks 6 # u & >> v1 16 255
            = . ks 7 # u & >> v1 24 255
            : i v2 # i x2
            = . ks 8 # u & v2 255
            = . ks 9 # u & >> v2 8 255
            = . ks 10 # u & >> v2 16 255
            = . ks 11 # u & >> v2 24 255
            : i v3 # i x3
            = . ks 12 # u & v3 255
            = . ks 13 # u & >> v3 8 255
            = . ks 14 # u & >> v3 16 255
            = . ks 15 # u & >> v3 24 255
            : i v4 # i x4
            = . ks 16 # u & v4 255
            = . ks 17 # u & >> v4 8 255
            = . ks 18 # u & >> v4 16 255
            = . ks 19 # u & >> v4 24 255
            : i v5 # i x5
            = . ks 20 # u & v5 255
            = . ks 21 # u & >> v5 8 255
            = . ks 22 # u & >> v5 16 255
            = . ks 23 # u & >> v5 24 255
            : i v6 # i x6
            = . ks 24 # u & v6 255
            = . ks 25 # u & >> v6 8 255
            = . ks 26 # u & >> v6 16 255
            = . ks 27 # u & >> v6 24 255
            : i v7 # i x7
            = . ks 28 # u & v7 255
            = . ks 29 # u & >> v7 8 255
            = . ks 30 # u & >> v7 16 255
            = . ks 31 # u & >> v7 24 255
            : i v8 # i x8
            = . ks 32 # u & v8 255
            = . ks 33 # u & >> v8 8 255
            = . ks 34 # u & >> v8 16 255
            = . ks 35 # u & >> v8 24 255
            : i v9 # i x9
            = . ks 36 # u & v9 255
            = . ks 37 # u & >> v9 8 255
            = . ks 38 # u & >> v9 16 255
            = . ks 39 # u & >> v9 24 255
            : i v10 # i x10
            = . ks 40 # u & v10 255
            = . ks 41 # u & >> v10 8 255
            = . ks 42 # u & >> v10 16 255
            = . ks 43 # u & >> v10 24 255
            : i v11 # i x11
            = . ks 44 # u & v11 255
            = . ks 45 # u & >> v11 8 255
            = . ks 46 # u & >> v11 16 255
            = . ks 47 # u & >> v11 24 255
            : i v12 # i x12
            = . ks 48 # u & v12 255
            = . ks 49 # u & >> v12 8 255
            = . ks 50 # u & >> v12 16 255
            = . ks 51 # u & >> v12 24 255
            : i v13 # i x13
            = . ks 52 # u & v13 255
            = . ks 53 # u & >> v13 8 255
            = . ks 54 # u & >> v13 16 255
            = . ks 55 # u & >> v13 24 255
            : i v14 # i x14
            = . ks 56 # u & v14 255
            = . ks 57 # u & >> v14 8 255
            = . ks 58 # u & >> v14 16 255
            = . ks 59 # u & >> v14 24 255
            : i v15 # i x15
            = . ks 60 # u & v15 255
            = . ks 61 # u & >> v15 8 255
            = . ks 62 # u & >> v15 16 255
            = . ks 63 # u & >> v15 24 255
            : ~ i j 0
            ~ < + off j n {
                = . op + off j # u ^^ # i . dp + off j # i . ks j
                = j + j 1
            }
        } {}
        = off + off 64
        = ctr + ctr 1
    }
    ^ out
}

// ── Poly1305 (radix 2^64) ──────────────────────────────────────────
// The accumulator is two full 64-bit words and a few bits above them
// (h = h2·2^128 + h1·2^64 + h0, h2 ≤ 7), and r is two words. The clamp
// leaves r1 a multiple of 4, so 2^130 ≡ 5 folds into s1 = r1 + r1/4
// (= 5·r1/4) exactly, and a block is FOUR 64×64→128 products plus two
// small ones (h2·s1, h2·r0) — against the nine of the radix-2^44 donna-64
// form this replaced, at 2.3 cycles a byte the larger half of every
// ChaCha20-Poly1305 record. This is the formulation OpenSSL's and
// BoringSSL's scalar x86-64 code use.

// Little-endian 64-bit load of the 8 bytes at `mp[off .. off+7]`, built
// from bytes so it is correct on any target and needs no alignment. The
// full-block path calls it at 8-aligned offsets, but the two `<< 32`
// halves keep it valid off-alignment too.
@ __ld64 * u mp i off → i {
    : i lo | | | # i . mp off << # i . mp + off 1 8 << # i . mp + off 2 16 << # i . mp + off 3 24
    : i hi | | | # i . mp + off 4 << # i . mp + off 5 8 << # i . mp + off 6 16 << # i . mp + off 7 24
    ^ | lo << hi 32
}

// h ← (h + m + pad·2^128) · r, partially reduced mod 2^130 − 5: the
// result's h2 stays below 8, which is all the next block's h2 products
// need.
inline @ __poly_block inout u64 h0 inout u64 h1 inout u64 h2 u64 t0 u64 t1 u64 pad u64 kr0 u64 kr1 u64 ks1 → v {
    // h += m
    : u64 a0 ( nurl_addc_lo h0 t0 0 )
    : u64 a1 ( nurl_addc_lo h1 t1 ( nurl_addc_hi h0 t0 0 ) )
    : u64 a2 + + h2 ( nurl_addc_hi h1 t1 ( nurl_addc_hi h0 t0 0 ) ) pad
    // d0 = a0·r0 + a1·s1
    : u64 x1 * a1 ks1
    : u64 d0lo ( nurl_mac_lo a0 kr0 x1 0 )
    : u64 d0hi + ( nurl_mac_hi a0 kr0 x1 0 ) ( nurl_umulhi a1 ks1 )
    // d1 = a0·r1 + a1·r0 + a2·s1
    : u64 e1 * a2 ks1
    : u64 p1lo ( nurl_mac_lo a0 kr1 e1 0 )
    : u64 p1hi ( nurl_mac_hi a0 kr1 e1 0 )
    : u64 d1lo ( nurl_mac_lo a1 kr0 p1lo 0 )
    : u64 d1hi + ( nurl_mac_hi a1 kr0 p1lo 0 ) p1hi
    // h = d0 + d1·2^64 + a2·r0·2^128
    : u64 g1 ( nurl_addc_lo d1lo d0hi 0 )
    : u64 g2 + + * a2 kr0 d1hi ( nurl_addc_hi d1lo d0hi 0 )
    // fold the bits above 2^130: c·2^130 ≡ 5c = (g2 & ~3) + (g2 >> 2)
    : u64 c + & g2 -4 >> g2 2
    = h0 ( nurl_addc_lo d0lo c 0 )
    : u64 k0 ( nurl_addc_hi d0lo c 0 )
    = h1 ( nurl_addc_lo g1 k0 0 )
    = h2 + & g2 3 ( nurl_addc_hi g1 k0 0 )
}

// `len` bytes at `p` into the accumulator as ⌈len/16⌉ blocks, a short
// last one zero-padded to 16 and still carrying the 2^128 bit — the
// AEAD's pad16 (RFC 8439 §2.8), so the MAC input is fed from where its
// pieces lie instead of concatenated into a buffer of its own. With
// `wide` (the caller built __poly_wide_key's table at `st`), whole
// 64-byte groups of a piece of 64 bytes or more go four blocks at a time.
unsafe @ __poly_feed16 inout u64 h0 inout u64 h1 inout u64 h2 * u p i len u64 kr0 u64 kr1 u64 ks1 * u st b wide → v {
    : i full & len -16
    : ~ i off 0
    ? & wide >= full 64 {
        : *u64 sp # *u64 st
        = . sp 0 h0 = . sp 1 h1 = . sp 2 h2
        = off ( __poly_wide st p full )
        = h0 . sp 0 = h1 . sp 1 = h2 . sp 2
    } {}
    ~ < off full {
        ( __poly_block h0 h1 h2 # u64 ( __ld64 p off ) # u64 ( __ld64 p + off 8 ) 1 kr0 kr1 ks1 )
        = off + off 16
    }
    ? < off len {
        : v128 t ( nurl_v128_ldn # s + # i p off - len off )
        ( __poly_block h0 h1 h2 # u64 ( nurl_v128_get64 t 0 ) # u64 ( nurl_v128_get64 t 1 ) 1 kr0 kr1 ks1 )
    } {}
}

// The tag: h mod p, plus s (the one-time key's second half, at `sp`),
// mod 2^128 — 16 little-endian bytes to `out`.
unsafe @ __poly_finish u64 h0 u64 h1 u64 h2 * u sp * u out → v {
    // h mod p: h + 5 reaches 2^130 exactly when h ≥ p (h < 2p here), and
    // then the low 128 bits of h + 5 are h − p's. Constant-time select.
    : u64 g0 ( nurl_addc_lo h0 5 0 )
    : u64 g1 ( nurl_addc_lo h1 0 ( nurl_addc_hi h0 5 0 ) )
    : u64 g2 + h2 ( nurl_addc_hi h1 0 ( nurl_addc_hi h0 5 0 ) )
    : u64 mask - 0 >> g2 2  // all ones when h ≥ p
    : u64 f0 | & h0 ~ mask & g0 mask
    : u64 f1 | & h1 ~ mask & g1 mask
    : u64 st0 # u64 ( __ld64 sp 0 )
    : u64 st1 # u64 ( __ld64 sp 8 )
    : u64 w0 ( nurl_addc_lo f0 st0 0 )
    : u64 w1 ( nurl_addc_lo f1 st1 ( nurl_addc_hi f0 st0 0 ) )
    ( nurl_v128_st # s out ( nurl_v128_set64 # i w0 # i w1 ) )
}

// ── Poly1305, four blocks at a time ─────────────────────────────────
// The radix-2^64 block above is a chain: each block's product waits on
// the last one's, so the multiplier sits idle most of every block. The
// vector form (Goll–Gueron, OpenSSL's and aws-lc's AVX2 Poly1305) breaks
// the chain into four: lane j of five v256 limb vectors (radix 2^26, one
// 64-bit lane per block, every limb product one `vpmuludq`) accumulates
// blocks j, j+4, j+8, …, each group of four as
//
//     H ← (H + M) · r^4
//
// and the last group instead by r^4, r^3, r^2, r^1 per lane, so that every
// block ends up multiplied by the power of r its position calls for. The
// lanes then add up to the scalar accumulator. Constant time: the same
// instructions for every input. Run where 256-bit vectors are native
// (the x86-64-v3 clone), like ChaCha20's eight-block kernel.
//
// Limbs stay below 2^27 between groups and r^k's below 2^27 (5·r^k's below
// 2^30), so every product fits vpmuludq's 32×32 → 64 and a five-term sum
// stays below 2^60.

// A 130-bit (w0, w1, w2) as five 26-bit limbs, the top one taking w2's
// bits whole. Every caller's w2 is below 8 (__poly_block keeps h2 there),
// so the top limb is below 2^27, and the mask says so: it is what lets the
// compiler see that every limb fits vpmuludq's 32 bits, and multiply a
// loop-invariant broadcast of one with a single instruction.
inline @ __pv_limbs u64 w0 u64 w1 u64 w2 inout u64 l0 inout u64 l1 inout u64 l2 inout u64 l3 inout u64 l4 → v {
    = l0 & w0 67108863
    = l1 & >> w0 26 67108863
    = l2 & | >> w0 52 << w1 12 67108863
    = l3 & >> w1 14 67108863
    = l4 & | >> w1 40 << w2 24 134217727
}

// Four blocks at `p` as limb vectors. The two loads hold blocks 0, 1 and
// 2, 3; interleaving their 64-bit halves puts blocks 0, 2, 1, 3 in lanes
// 0 … 3 — an order the final powers follow, so no cross-lane permute.
// Every block carries its 2^128 bit (limb 4, bit 24).
inline @ __pv_msg * u p inout v256 m0 inout v256 m1 inout v256 m2 inout v256 m3 inout v256 m4 → v {
    : v256 a ( nurl_v256_ld # s p )
    : v256 b ( nurl_v256_ld # s + # i p 32 )
    : v256 lo ( nurl_v256_unpacklo64 a b )
    : v256 hi ( nurl_v256_unpackhi64 a b )
    : v256 mk ( nurl_v256_bcast64 67108863 )
    = m0 ( nurl_v256_and lo mk )
    = m1 ( nurl_v256_and ( nurl_v256_shr64 lo 26 ) mk )
    = m2 ( nurl_v256_and ( nurl_v256_or ( nurl_v256_shr64 lo 52 ) ( nurl_v256_shl64 hi 12 ) ) mk )
    = m3 ( nurl_v256_and ( nurl_v256_shr64 hi 14 ) mk )
    = m4 ( nurl_v256_or ( nurl_v256_shr64 hi 40 ) ( nurl_v256_bcast64 16777216 ) )
}

// One lane's limb: low 26 bits kept, the rest carried into `into`.
inline @ __pv_carry inout v256 from inout v256 into → v {
    = into ( nurl_v256_add64 into ( nurl_v256_shr64 from 26 ) )
    = from ( nurl_v256_and from ( nurl_v256_bcast64 67108863 ) )
}

// d ← h · r per lane (s_i = 5·r_i: 2^130 ≡ 5): the five 64-bit column
// sums, not yet carried back to 26-bit limbs (__pv_norm).
inline @ __pv_prod inout v256 d0 inout v256 d1 inout v256 d2 inout v256 d3 inout v256 d4 v256 h0 v256 h1 v256 h2 v256 h3 v256 h4 v256 k0 v256 k1 v256 k2 v256 k3 v256 k4 v256 s1 v256 s2 v256 s3 v256 s4 → v {
    = d0 ( nurl_v256_mul32u h0 k0 )
    = d1 ( nurl_v256_mul32u h0 k1 )
    = d2 ( nurl_v256_mul32u h0 k2 )
    = d3 ( nurl_v256_mul32u h0 k3 )
    = d4 ( nurl_v256_mul32u h0 k4 )
    = d0 ( nurl_v256_add64 d0 ( nurl_v256_mul32u h1 s4 ) )
    = d1 ( nurl_v256_add64 d1 ( nurl_v256_mul32u h1 k0 ) )
    = d2 ( nurl_v256_add64 d2 ( nurl_v256_mul32u h1 k1 ) )
    = d3 ( nurl_v256_add64 d3 ( nurl_v256_mul32u h1 k2 ) )
    = d4 ( nurl_v256_add64 d4 ( nurl_v256_mul32u h1 k3 ) )
    = d0 ( nurl_v256_add64 d0 ( nurl_v256_mul32u h2 s3 ) )
    = d1 ( nurl_v256_add64 d1 ( nurl_v256_mul32u h2 s4 ) )
    = d2 ( nurl_v256_add64 d2 ( nurl_v256_mul32u h2 k0 ) )
    = d3 ( nurl_v256_add64 d3 ( nurl_v256_mul32u h2 k1 ) )
    = d4 ( nurl_v256_add64 d4 ( nurl_v256_mul32u h2 k2 ) )
    = d0 ( nurl_v256_add64 d0 ( nurl_v256_mul32u h3 s2 ) )
    = d1 ( nurl_v256_add64 d1 ( nurl_v256_mul32u h3 s3 ) )
    = d2 ( nurl_v256_add64 d2 ( nurl_v256_mul32u h3 s4 ) )
    = d3 ( nurl_v256_add64 d3 ( nurl_v256_mul32u h3 k0 ) )
    = d4 ( nurl_v256_add64 d4 ( nurl_v256_mul32u h3 k1 ) )
    = d0 ( nurl_v256_add64 d0 ( nurl_v256_mul32u h4 s1 ) )
    = d1 ( nurl_v256_add64 d1 ( nurl_v256_mul32u h4 s2 ) )
    = d2 ( nurl_v256_add64 d2 ( nurl_v256_mul32u h4 s3 ) )
    = d3 ( nurl_v256_add64 d3 ( nurl_v256_mul32u h4 s4 ) )
    = d4 ( nurl_v256_add64 d4 ( nurl_v256_mul32u h4 k0 ) )
}

// The column sums back to 26-bit limbs (the top one a little over):
// OpenSSL's order, two chains interleaved, the top carry folded into
// limb 0 as ×5.
inline @ __pv_norm inout v256 d0 inout v256 d1 inout v256 d2 inout v256 d3 inout v256 d4 → v {
    ( __pv_carry d3 d4 )
    ( __pv_carry d0 d1 )
    // d4's carry wraps to d0 as ×5
    : v256 c4 ( nurl_v256_shr64 d4 26 )
    = d4 ( nurl_v256_and d4 ( nurl_v256_bcast64 67108863 ) )
    = d0 ( nurl_v256_add64 d0 ( nurl_v256_add64 c4 ( nurl_v256_shl64 c4 2 ) ) )
    ( __pv_carry d1 d2 )
    ( __pv_carry d2 d3 )
    ( __pv_carry d0 d1 )
    ( __pv_carry d3 d4 )
}

// The key's table for __poly_wide, at `st + 32` (the accumulator's three
// words are at `st`): four sets of multipliers, each nine vectors — the
// five limbs of a power of r per lane and the fives of the top four
// (2^130 ≡ 5) — 288 bytes a set:
//
//     t +   0   r^4 in every lane          one group alone (an odd count)
//     t + 288   r^8 in every lane          the two-group loop
//     t + 576   r^8, r^6, r^7, r^5         the second-to-last group
//     t + 864   r^4, r^2, r^3, r^1         the last group
//
// (lanes hold blocks 0, 2, 1, 3 — __pv_msg), and past them, at
// `st + 1184`, the limbs of r^1 … r^8 they are made from: `st` is 1504
// bytes of scratch. The table is MEMORY on purpose, as in OpenSSL's and aws-lc's:
// the kernel loads it, so its multipliers are values the compiler knows
// nothing about and masks next to each `vpmuludq`. Built in the kernel
// itself, a broadcast of a limb the optimiser had proven small left the
// loop as a vector whose bounds the backend could no longer see, and
// every product cost three multiplies. r = (kr0, kr1), clamped.
unsafe @ __poly_wide_key * u st u64 kr0 u64 kr1 → v {
    : u64 s1 + kr1 >> kr1 2
    : *u64 pp # *u64 + # i st 1184
    // pp[5(k−1) + i] = limb i of r^k, k = 1 … 8, by the scalar block
    // (h = r^k, no message)
    : ~ u64 a0 kr0
    : ~ u64 a1 kr1
    : ~ u64 a2 0
    : ~ i k 0
    ~ < k 8 {
        : ~ u64 l0 0
        : ~ u64 l1 0
        : ~ u64 l2 0
        : ~ u64 l3 0
        : ~ u64 l4 0
        ( __pv_limbs a0 a1 a2 l0 l1 l2 l3 l4 )
        : i o * k 5
        = . pp o l0 = . pp + o 1 l1 = . pp + o 2 l2 = . pp + o 3 l3 = . pp + o 4 l4
        ( __poly_block a0 a1 a2 0 0 0 kr0 kr1 s1 )
        = k + k 1
    }
    : i t + # i st 32
    ( __pv_put_set t pp 4 4 4 4 )
    ( __pv_put_set + t 288 pp 8 8 8 8 )
    ( __pv_put_set + t 576 pp 8 6 7 5 )
    ( __pv_put_set + t 864 pp 4 2 3 1 )
}

// One set at `at`: lane j gets r^(e_j) (exponents a, b, c, d), limbs from
// the power table `pp` (__poly_wide_key).
unsafe @ __pv_put_set i at * u64 pp i a i b i c i d → v {
    : ~ i li 0
    ~ < li 5 {
        : u64 xa . pp + * - a 1 5 li
        : u64 xb . pp + * - b 1 5 li
        : u64 xc . pp + * - c 1 5 li
        : u64 xd . pp + * - d 1 5 li
        ( nurl_v256_st # s + at * li 32 ( nurl_v256_set64 # i xa # i xb # i xc # i xd ) )
        ? > li 0 {
            ( nurl_v256_st # s + + at 128 * li 32 ( nurl_v256_set64 # i * xa 5 # i * xb 5 # i * xc 5 # i * xd 5 ) )
        } {}
        = li + li 1
    }
}

// d ← h · (the set at `at`), per lane, uncarried.
inline @ __pv_mulset inout v256 d0 inout v256 d1 inout v256 d2 inout v256 d3 inout v256 d4 v256 h0 v256 h1 v256 h2 v256 h3 v256 h4 i at → v {
    ( __pv_prod d0 d1 d2 d3 d4 h0 h1 h2 h3 h4
    ( nurl_v256_ld # s at ) ( nurl_v256_ld # s + at 32 ) ( nurl_v256_ld # s + at 64 )
    ( nurl_v256_ld # s + at 96 ) ( nurl_v256_ld # s + at 128 )
    ( nurl_v256_ld # s + at 160 ) ( nurl_v256_ld # s + at 192 ) ( nurl_v256_ld # s + at 224 )
    ( nurl_v256_ld # s + at 256 ) )
}

// One group: d holds the accumulator as uncarried column sums; carry it
// to limbs, add the four blocks at `p`, multiply by the set at `at`.
//
// The accumulator crosses the loop's back edge UNCARRIED on purpose. A
// limb vector that crosses it is, to the code generator, a value from
// another block whose high bits it cannot know — while the optimiser,
// which can prove them zero, has dropped the mask `vpmuludq` needs — and
// the product then costs three multiplies and two shifts. Carried here,
// each limb is derived in the block that multiplies it, mask and all.
inline @ __pv_step inout v256 d0 inout v256 d1 inout v256 d2 inout v256 d3 inout v256 d4 * u p i at → v {
    ( __pv_norm d0 d1 d2 d3 d4 )
    : ~ v256 m0 ( nurl_v256_zero )
    : ~ v256 m1 ( nurl_v256_zero )
    : ~ v256 m2 ( nurl_v256_zero )
    : ~ v256 m3 ( nurl_v256_zero )
    : ~ v256 m4 ( nurl_v256_zero )
    ( __pv_msg p m0 m1 m2 m3 m4 )
    : v256 h0 ( nurl_v256_add64 d0 m0 )
    : v256 h1 ( nurl_v256_add64 d1 m1 )
    : v256 h2 ( nurl_v256_add64 d2 m2 )
    : v256 h3 ( nurl_v256_add64 d3 m3 )
    : v256 h4 ( nurl_v256_add64 d4 m4 )
    ( __pv_mulset d0 d1 d2 d3 d4 h0 h1 h2 h3 h4 at )
}

// Whole 64-byte groups of the `n` bytes at `p` (n ≥ 64) into the
// accumulator (h0, h1, h2) held at `st`, under the table
// __poly_wide_key built there. Returns the bytes consumed, a multiple of
// 64. Two accumulators, A and B, take the groups in turn, each
// multiplied by r^8 — two independent chains, so one group's multiply
// overlaps the other's carries — and the last two groups by the per-lane
// powers that put every block where its position says: block 4g + b of
// N blocks ends up multiplied by r^(N − 4g − b). An odd group count
// starts with one group alone by r^4. Callers ask __poly_wide_ok first,
// so the x86-64-v3 clone is the one that runs (the baseline clone is the
// same arithmetic in SSE2 halves: correct, never chosen).
unsafe simd @ __poly_wide * u st * u p i n → i {
    : *u64 sp # *u64 st
    : i t + # i st 32
    // the accumulator so far, in lane 0 of A
    : ~ u64 q0 0
    : ~ u64 q1 0
    : ~ u64 q2 0
    : ~ u64 q3 0
    : ~ u64 q4 0
    ( __pv_limbs . sp 0 . sp 1 . sp 2 q0 q1 q2 q3 q4 )
    : ~ v256 a0 ( nurl_v256_set64 # i q0 0 0 0 )
    : ~ v256 a1 ( nurl_v256_set64 # i q1 0 0 0 )
    : ~ v256 a2 ( nurl_v256_set64 # i q2 0 0 0 )
    : ~ v256 a3 ( nurl_v256_set64 # i q3 0 0 0 )
    : ~ v256 a4 ( nurl_v256_set64 # i q4 0 0 0 )
    : ~ v256 b0 ( nurl_v256_zero )
    : ~ v256 b1 ( nurl_v256_zero )
    : ~ v256 b2 ( nurl_v256_zero )
    : ~ v256 b3 ( nurl_v256_zero )
    : ~ v256 b4 ( nurl_v256_zero )
    : i k / n 64
    : i used * k 64
    : i base # i p
    ? == k 1 {
        ( __pv_step a0 a1 a2 a3 a4 p + t 864 )
    } {
        : ~ i off 0
        ? == % k 2 1 {
            ( __pv_step a0 a1 a2 a3 a4 p t )
            = off 64
        } {}
        ~ < + off 128 used {
            ( __pv_step a0 a1 a2 a3 a4 # *u + base off + t 288 )
            ( __pv_step b0 b1 b2 b3 b4 # *u + + base off 64 + t 288 )
            = off + off 128
        }
        ( __pv_step a0 a1 a2 a3 a4 # *u + base off + t 576 )
        ( __pv_step b0 b1 b2 b3 b4 # *u + + base off 64 + t 864 )
    }
    ( __pv_norm a0 a1 a2 a3 a4 )
    ( __pv_norm b0 b1 b2 b3 b4 )
    = a0 ( nurl_v256_add64 a0 b0 )
    = a1 ( nurl_v256_add64 a1 b1 )
    = a2 ( nurl_v256_add64 a2 b2 )
    = a3 ( nurl_v256_add64 a3 b3 )
    = a4 ( nurl_v256_add64 a4 b4 )
    // add the lanes up, back to radix 2^64
    : u64 t0 + + + ( nurl_v256_get64 a0 0 ) ( nurl_v256_get64 a0 1 ) ( nurl_v256_get64 a0 2 ) ( nurl_v256_get64 a0 3 )
    : u64 t1 + + + ( nurl_v256_get64 a1 0 ) ( nurl_v256_get64 a1 1 ) ( nurl_v256_get64 a1 2 ) ( nurl_v256_get64 a1 3 )
    : u64 t2 + + + ( nurl_v256_get64 a2 0 ) ( nurl_v256_get64 a2 1 ) ( nurl_v256_get64 a2 2 ) ( nurl_v256_get64 a2 3 )
    : u64 t3 + + + ( nurl_v256_get64 a3 0 ) ( nurl_v256_get64 a3 1 ) ( nurl_v256_get64 a3 2 ) ( nurl_v256_get64 a3 3 )
    : u64 t4 + + + ( nurl_v256_get64 a4 0 ) ( nurl_v256_get64 a4 1 ) ( nurl_v256_get64 a4 2 ) ( nurl_v256_get64 a4 3 )
    : u64 x + t0 << t1 26
    : u64 lo2 << t2 52
    : u64 w0 ( nurl_addc_lo x lo2 0 )
    : u64 c0 ( nurl_addc_hi x lo2 0 )
    : u64 y + >> t2 12 << t3 14
    : u64 lo4 << t4 40
    : u64 w1 ( nurl_addc_lo y lo4 c0 )
    : u64 w2 + >> t4 24 ( nurl_addc_hi y lo4 c0 )
    // fold the bits above 2^130 (×5) so h2 is back below 8
    : u64 f * >> w2 2 5
    = . sp 0 ( nurl_addc_lo w0 f 0 )
    : u64 k0 ( nurl_addc_hi w0 f 0 )
    = . sp 1 ( nurl_addc_lo w1 0 k0 )
    = . sp 2 + & w2 3 ( nurl_addc_hi w1 0 k0 )
    ^ used
}

// Is the vector kernel worth building a table for, for a MAC over
// `len` bytes? It needs 256-bit vectors, and below 256 bytes its setup —
// three scalar products for r's powers, the table, the lane sum — costs
// more than it saves.
@ __poly_wide_ok i len → b {
    ^ & >= len 256 != 0 # i ( nurl_cpu_x86_v3 )
}

// otk = 32-byte one-time key (r || s). Returns the 16-byte tag, or an
// empty Vec for a key that is not 32 bytes.
@ poly1305_mac ( Vec u ) otk ( Vec u ) msg → ( Vec u ) {
    ? != ( vec_len [u] otk ) 32 { ^ ( vec_new [u] ) } {}
    : *u kp ( vec_data [u] otk )
    // RFC 8439's clamp on the two little-endian words of r
    : u64 r0 & # u64 ( __ld64 kp 0 ) 0x0ffffffc0fffffff
    : u64 r1 & # u64 ( __ld64 kp 8 ) 0x0ffffffc0ffffffc
    : u64 s1 + r1 >> r1 2

    : ~ u64 h0 0
    : ~ u64 h1 0
    : ~ u64 h2 0

    : i mlen ( vec_len [u] msg )
    : *u mp ( vec_data [u] msg )
    : i full & mlen -16
    : ~ i off 0
    // The tag's buffer is __poly_wide's scratch until the tag is written.
    : ( Vec u ) tag ( vec_with_cap [u] 1504 )
    ? ( __poly_wide_ok full ) {
        : *u st ( vec_data [u] tag )
        : *u64 sp # *u64 st
        ( __poly_wide_key st r0 r1 )
        = . sp 0 h0 = . sp 1 h1 = . sp 2 h2
        = off ( __poly_wide st mp full )
        = h0 . sp 0 = h1 . sp 1 = h2 . sp 2
    } {}
    ~ < off full {
        ( __poly_block h0 h1 h2 # u64 ( __ld64 mp off ) # u64 ( __ld64 mp + off 8 ) 1 r0 r1 s1 )
        = off + off 16
    }
    ? < off mlen {
        // Tail: the remaining bytes, zero-padded to 16, with the 0x01
        // marker byte after them — assembled little-endian straight into
        // t0/t1 — and no 2^128 bit: the marker rides inside the block.
        : i blk - mlen off
        : ~ u64 t0 0
        : ~ u64 t1 0
        : ~ i j 0
        ~ <= j blk {
            : u64 bv ? < j blk # u64 . mp + off j # u64 1
            ? < j 8 { = t0 | t0 << bv # u64 * 8 j } { = t1 | t1 << bv # u64 * 8 - j 8 }
            = j + j 1
        }
        ( __poly_block h0 h1 h2 t0 t1 0 r0 r1 s1 )
    } {}

    // h mod p: h + 5 reaches 2^130 exactly when h ≥ p (h < 2p here), and
    // then the low 128 bits of h + 5 are h − p's. Constant-time select.
    : u64 g0 ( nurl_addc_lo h0 5 0 )
    : u64 g1 ( nurl_addc_lo h1 0 ( nurl_addc_hi h0 5 0 ) )
    : u64 g2 + h2 ( nurl_addc_hi h1 0 ( nurl_addc_hi h0 5 0 ) )
    : u64 mask - 0 >> g2 2  // all ones when h ≥ p
    : u64 f0 | & h0 ~ mask & g0 mask
    : u64 f1 | & h1 ~ mask & g1 mask

    // tag = (h + s) mod 2^128
    : u64 st0 # u64 ( __ld64 kp 16 )
    : u64 st1 # u64 ( __ld64 kp 24 )
    : u64 w0 ( nurl_addc_lo f0 st0 0 )
    : u64 w1 ( nurl_addc_lo f1 st1 ( nurl_addc_hi f0 st0 0 ) )
    ( __push_le32 tag # i & w0 4294967295 )
    ( __push_le32 tag # i & >> w0 32 4294967295 )
    ( __push_le32 tag # i & w1 4294967295 )
    ( __push_le32 tag # i & >> w1 32 4294967295 )
    ^ tag
}

// ── ChaCha20-Poly1305 AEAD (RFC 8439 §2.8) ────────────────────────
// The one-time Poly1305 key: first 32 bytes of the counter-0 block.
@ __poly_key ( Vec u ) key ( Vec u ) nonce → ( Vec u ) {
    // Only the first half of the counter-0 block is the key, so ask the
    // kernel for 32 bytes and skip both the second half and the copy out
    // of it. One of these per AEAD record.
    : ( Vec u ) z ( __zeros 32 )
    : ( Vec u ) otk ( chacha20_xor_range key 0 nonce z 0 32 )
    ^ otk
}

@ __pad16 ( Vec u ) v i len → v {
    : i r & len 15
    ? != r 0 {
        : ~ i p - 16 r
        ~ > p 0 { ( vec_push [u] v # u 0 ) = p - p 1 }
    } {}
}

@ __push_le64 ( Vec u ) v i n → v {
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] v # u & >> n * 8 k 255 ) = k + k 1 }
}

// Build the Poly1305 input: aad ‖ pad16 ‖ ct ‖ pad16 ‖ le64(|aad|) ‖ le64(|ct|),
// where the ciphertext is the `cl` bytes of `ct` at `coff` — decrypt hands
// in the record buffer with the tag still on the end rather than a copy.
@ __mac_data ( Vec u ) aad ( Vec u ) ct i coff i cl → ( Vec u ) {
    : i al ( vec_len [u] aad )
    : ( Vec u ) m ( vec_with_cap [u] + + al cl 32 )
    // Bulk pointer copies, not per-byte checked pushes: the ciphertext
    // side is the whole record and this concat sat at ~4% of a TLS
    // transfer on its own.
    : b _ml ( vec_set_len [u] m al )
    : *u mp ( vec_data [u] m )
    : *u ap ( vec_data [u] aad )
    : ~ i i 0
    ~ < i al { = . mp i . ap i = i + i 1 }
    ( __pad16 m al )
    : i cbase ( vec_len [u] m )
    : b _cl ( vec_set_len [u] m + cbase cl )
    : *u mp2 ( vec_data [u] m )
    : *u cp # *u + # i ( vec_data [u] ct ) coff
    = i 0
    ~ < i cl { = . mp2 + cbase i . cp i = i + i 1 }
    ( __pad16 m cl )
    ( __push_le64 m al )
    ( __push_le64 m cl )
    ^ m
}

// Encrypt: returns ciphertext with the 16-byte tag appended.
@ aead_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) plaintext → ( Vec u ) {
    // M5/L6: 32-byte key, 12-byte nonce, and the ChaCha20 keystream limit
    // (2^32 blocks × 64 B); past it the 32-bit block counter wraps and
    // reuses keystream. A wrong nonce length would otherwise risk reuse.
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ ( vec_new [u] ) } {}
    ? > ( vec_len [u] plaintext ) 274877906880 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) otk ( __poly_key key nonce )
    : ( Vec u ) ct ( chacha20_xor key 1 nonce plaintext )
    : ( Vec u ) md ( __mac_data aad ct 0 ( vec_len [u] ct ) )
    : ( Vec u ) tag ( poly1305_mac otk md )
    : ~ i k 0
    ~ < k 16 { ( vec_push [u] ct # u ( __cc_bget tag k ) ) = k + k 1 }
    ^ ct
}

// Constant-time tag comparison over the trailing 16 bytes of `ct_and_tag`.
@ __tag_ok ( Vec u ) ct_and_tag i ctlen ( Vec u ) want → b {
    : ~ i diff 0
    : ~ i k 0
    ~ < k 16 {
        = diff | diff ^^ ( __cc_bget ct_and_tag + ctlen k ) ( __cc_bget want k )
        = k + k 1
    }
    ^ == diff 0
}

// Decrypt + verify. ct_and_tag is ciphertext followed by its 16-byte
// tag. Returns None on any tampering (wrong tag), the plaintext on success.
@ aead_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_and_tag → ?( Vec u ) {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : i total ( vec_len [u] ct_and_tag )
    ? < total 16 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : i ctlen - total 16
    // The ciphertext is `ct_and_tag` minus its trailing tag — both the MAC
    // and the keystream take it as a range, so nothing is copied out of
    // the record to name it. Extracting it used to cost a bounds-checked
    // `vec_get` + `vec_push` PER BYTE of every 16 KB record, a quarter of
    // the whole receive path.
    : ( Vec u ) otk ( __poly_key key nonce )
    : ( Vec u ) md ( __mac_data aad ct_and_tag 0 ctlen )
    : ( Vec u ) tag ( poly1305_mac otk md )
    : b ok ( __tag_ok ct_and_tag ctlen tag )
    ? ! ok { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : ( Vec u ) pt ( chacha20_xor_range key 1 nonce ct_and_tag 0 ctlen )
    ^ @ ?( Vec u ) { T pt }
}

// ── In place, with a sequence-number nonce ─────────────────────────
// The record layer's form (as aes_gcm_seal_in / aes_gcm_open_in): the
// record sealed or opened where it lies in its own buffer, the nonce the
// 12-byte `iv` with the 64-bit `seq` big-endian XORed into its last 8
// bytes (RFC 8446 §5.3, RFC 9001 §5.3), the Poly1305 input fed from the
// AAD and the ciphertext where they lie. The scratch — keystream, the
// one-time key, the nonce and the tag — is the buffer's spare capacity
// past its length, reserved here: 16-aligned past room for the tag.

// Scratch layout from __xor_scratch_at len: keystream [0, 128), the
// one-time key block [128, 192), the nonce [192, 204), the tag [208, 224),
// the Poly1305 accumulator and key table [224, 1728) (__poly_wide_key).
@ __ccp_scratch → i { ^ 1728 }

// The MAC of `aad` (at `ap`, `al` bytes) and the ciphertext (at `cp`,
// `cl` bytes) under the one-time key at `kp`: pad16 pieces, then the two
// little-endian lengths. Tag to `out`; `st`, 1504 bytes of scratch.
unsafe @ __ccp_mac * u kp * u ap i al * u cp i cl * u out * u st → v {
    : u64 r0 & # u64 ( __ld64 kp 0 ) 0x0ffffffc0fffffff
    : u64 r1 & # u64 ( __ld64 kp 8 ) 0x0ffffffc0ffffffc
    : u64 s1 + r1 >> r1 2
    : ~ u64 h0 0
    : ~ u64 h1 0
    : ~ u64 h2 0
    : b wide ( __poly_wide_ok + al cl )
    ? wide { ( __poly_wide_key st r0 r1 ) } {}
    ( __poly_feed16 h0 h1 h2 ap al r0 r1 s1 st wide )
    ( __poly_feed16 h0 h1 h2 cp cl r0 r1 s1 st wide )
    ( __poly_block h0 h1 h2 # u64 al # u64 cl 1 r0 r1 s1 )
    ( __poly_finish h0 h1 h2 # *u + # i kp 16 out )
}

// The nonce for (iv, seq) at `np`; the one-time key block (counter 0) at
// `kp`. F on a big-endian host, where the vector block kernel does not
// apply — the caller takes the Vec path then.
unsafe @ __ccp_setup ( Vec u ) key ( Vec u ) iv i seq * u np * u kp → b {
    ? == 0 ( __le_words ) { ^ F } {}
    : *u ivp ( vec_data [u] iv )
    : ~ i b 0
    ~ < b 4 { = . np b . ivp b = b + b 1 }
    ~ < b 12 {
        = . np b # u ^^ # i . ivp b & >> seq * 8 - 11 b 255
        = b + b 1
    }
    : v128 s0 ( nurl_v128_set32 1634760805 857760878 2036477234 1797285236 )
    : v128 s1 ( nurl_v128_set32 ( __ld32 key 0 ) ( __ld32 key 4 ) ( __ld32 key 8 ) ( __ld32 key 12 ) )
    : v128 s2 ( nurl_v128_set32 ( __ld32 key 16 ) ( __ld32 key 20 ) ( __ld32 key 24 ) ( __ld32 key 28 ) )
    ( __chacha20_block_v128 s0 s1 s2 ( nurl_v128_set32 0 # i ( __ld32le_p np 0 ) # i ( __ld32le_p np 4 ) # i ( __ld32le_p np 8 ) ) kp )
    ^ T
}

// The (iv, seq) nonce as a Vec, for the big-endian fallback.
@ __ccp_nonce_vec ( Vec u ) iv i seq → ( Vec u ) {
    : ( Vec u ) n ( vec_zeroed [u] 12 )
    : ~ i b 0
    ~ < b 12 {
        : i sb ? < b 4 0 & >> seq * 8 - 11 b 255
        ( vec_put [u] n b # u ^^ ( __cc_bget iv b ) sb )
        = b + b 1
    }
    ^ n
}

// Seal `buf[data_at, len)` in place, the AAD `buf[aad_at, data_at)`, and
// append the 16-byte tag. F — and `buf` untouched — for a key that is
// not 32 bytes, an iv that is not 12, offsets out of order, or a
// plaintext past the 32-bit block counter.
@ chacha20poly1305_seal_in ( Vec u ) key ( Vec u ) iv i seq ( Vec u ) buf i aad_at i data_at → b {
    : i len ( vec_len [u] buf )
    ? | | != ( vec_len [u] key ) 32 != ( vec_len [u] iv ) 12 | | < aad_at 0 > aad_at data_at > data_at len { ^ F } {}
    : i n - len data_at
    ? > n 274877906880 { ^ F } {}
    : i at ( __xor_scratch_at len )
    ( vec_reserve [u] buf + - at len ( __ccp_scratch ) )
    : *u base ( vec_data [u] buf )
    : *u scr # *u + # i base at
    : *u kp # *u + # i scr 128
    : *u np # *u + # i scr 192
    : *u dp # *u + # i base data_at
    ? ( __ccp_setup key iv seq np kp ) {
        ( __chacha20_xor_ptr key 1 # i ( __ld32le_p np 0 ) # i ( __ld32le_p np 4 ) # i ( __ld32le_p np 8 ) dp dp n scr )
        ( __ccp_mac kp # *u + # i base aad_at - data_at aad_at dp n # *u + # i scr 208 # *u + # i scr 224 )
        ( bytes_extend_raw_cc buf # *u + # i scr 208 16 )
        ^ T
    } {}
    // Big-endian host: the Vec path, copied back.
    : ( Vec u ) aad ( bytes_range_cc buf aad_at data_at )
    : ( Vec u ) pt ( bytes_range_cc buf data_at len )
    : ( Vec u ) sealed ( aead_encrypt key ( __ccp_nonce_vec iv seq ) aad pt )
    : b _l ( vec_set_len [u] buf data_at )
    ( bytes_extend_raw_cc buf ( vec_data [u] sealed ) ( vec_len [u] sealed ) )
    ^ T
}

// Open `buf[data_at, end)` — ciphertext, then its 16-byte tag — in
// place: the tag is checked over the ciphertext FIRST, and only then is
// it decrypted, so on T `buf[data_at, end - 16)` is the plaintext. The
// AAD is `buf[aad_at, data_at)`; bytes past `end` are left alone. On F
// (a wrong tag, or the argument errors of chacha20poly1305_seal_in) the
// range is zeroed.
@ chacha20poly1305_open_in ( Vec u ) key ( Vec u ) iv i seq ( Vec u ) buf i aad_at i data_at i end → b {
    : i len ( vec_len [u] buf )
    ? | | != ( vec_len [u] key ) 32 != ( vec_len [u] iv ) 12 | | < aad_at 0 > aad_at data_at | | < end 16 > end len > data_at - end 16 { ^ F } {}
    : i n - - end data_at 16
    : i at ( __xor_scratch_at len )
    ( vec_reserve [u] buf + - at len ( __ccp_scratch ) )
    : *u base ( vec_data [u] buf )
    : *u scr # *u + # i base at
    : *u kp # *u + # i scr 128
    : *u np # *u + # i scr 192
    : *u dp # *u + # i base data_at
    ? ( __ccp_setup key iv seq np kp ) {
        ( __ccp_mac kp # *u + # i base aad_at - data_at aad_at dp n # *u + # i scr 208 # *u + # i scr 224 )
        : ~ i diff 0
        : ~ i k 0
        ~ < k 16 { = diff | diff ^^ # i . scr + 208 k # i . dp + n k = k + k 1 }
        ? == diff 0 {
            ( __chacha20_xor_ptr key 1 # i ( __ld32le_p np 0 ) # i ( __ld32le_p np 4 ) # i ( __ld32le_p np 8 ) dp dp n scr )
            ^ T
        } {}
        ( nurl_memset # s dp 0 n )
        ^ F
    } {}
    // Big-endian host: the Vec path, copied back.
    : ( Vec u ) aad ( bytes_range_cc buf aad_at data_at )
    : ( Vec u ) ct ( bytes_range_cc buf data_at end )
    ?? ( aead_decrypt key ( __ccp_nonce_vec iv seq ) aad ct ) {
        T pt → {
            ( nurl_memcpy # s + # i ( vec_data [u] buf ) data_at # s ( vec_data [u] pt ) n )
            ^ T
        }
        F _ → {
            ( nurl_memset # s + # i ( vec_data [u] buf ) data_at 0 n )
            ^ F
        }
    }
}

// A little-endian u32 at `p + off`.
@ __ld32le_p * u p i off → u64 {
    ^ # u64 | | | # i . p off << # i . p + off 1 8 << # i . p + off 2 16 << # i . p + off 3 24
}

// `n` bytes from `src` appended to `v` (this file imports no bytes.nu).
@ bytes_extend_raw_cc ( Vec u ) v * u src i n → v {
    ( vec_reserve [u] v n )
    : i len ( vec_len [u] v )
    ( nurl_memcpy # s + # i ( vec_data [u] v ) len # s src n )
    : b _l ( vec_set_len [u] v + len n )
}

// A copy of `v[lo, hi)`.
// requires: 0 ≤ lo ≤ hi ≤ vec_len v (the seal/open callers check it).
raw @ bytes_range_cc ( Vec u ) v i lo i hi → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] - hi lo )
    ( bytes_extend_raw_cc out # *u + # i ( vec_data [u] v ) lo - hi lo )
    ^ out
}
