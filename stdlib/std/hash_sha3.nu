// stdlib/std/hash_sha3.nu — FIPS 202 SHA-3 and SHAKE in pure NURL.
//
// The Keccak sponge, the last of the standard hash families stdlib was
// missing. SHA-3 rounds out the digest set beside SHA-2 and BLAKE; SHAKE
// is the part with no substitute anywhere else in the tree — an
// extendable-output function that keeps producing bytes for as long as
// the caller pulls on it. ML-KEM (FIPS 203) is built almost entirely out
// of SHAKE: it derives its public matrix by squeezing SHAKE128 three
// bytes at a time until enough coefficients land in range, so the
// incremental squeeze below is a load-bearing API, not a convenience.
//
// API — one-shot digests:
//   ( sha3_224_pure ( Vec u ) data ) → ( Vec u )   28-byte digest
//   ( sha3_256_pure ( Vec u ) data ) → ( Vec u )   32-byte digest
//   ( sha3_384_pure ( Vec u ) data ) → ( Vec u )   48-byte digest
//   ( sha3_512_pure ( Vec u ) data ) → ( Vec u )   64-byte digest
//
// API — one-shot XOF (caller names the output length):
//   ( shake128_pure ( Vec u ) data i outlen ) → ( Vec u )
//   ( shake256_pure ( Vec u ) data i outlen ) → ( Vec u )
//
// API — streaming sponge, absorb then squeeze:
//   ( sha3_new i rate i domain )      → *Sha3
//   ( shake128_init )                 → *Sha3     rate 168
//   ( shake256_init )                 → *Sha3     rate 136
//   ( sha3_absorb *Sha3 h ( Vec u ) ) → v         any piece size, any count
//   ( sha3_squeeze *Sha3 h i n )      → ( Vec u ) call repeatedly; the
//                                                 stream continues where
//                                                 the last call stopped
//   ( sha3_free *Sha3 h )             → v
//
// The first `sha3_squeeze` closes absorption (pad10*1 with the domain
// byte) automatically; absorbing after that is a programming error and
// is ignored. The one-shot entries above are thin compositions of the
// streaming ones, so the two paths cannot drift.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// ── Keccak-f[1600] ─────────────────────────────────────────────────
//
// State is 25 lanes of 64 bits, indexed i = x + 5y. Twenty-four rounds
// of θ (column parity), ρ (per-lane rotation), π (lane permutation), χ
// (the row-wise non-linear step) and ι (round constant into lane 0).

// Left-rotate a u64 by c bits. One `rol` instruction via the compiler's
// funnel-shift primitive — see __sha256_rotr for why the shift/or pair
// this replaces was worth removing.
@ __k_rotl u64 x i c → u64 {
    ^ # u64 ( nurl_rotl64 # u64 x # u64 c )
}

// The 24 ι round constants (FIPS 202 §3.2.5). Written as their
// two's-complement i64 where they exceed 2^63-1: NURL has no hex
// literals, and `# u64 -N` reinterprets the bit pattern.
@ __keccak_rc → ( Vec u64 ) {
    : ( Vec u64 ) v ( vec_with_cap [u64] 24 )
    : b _l ( vec_set_len [u64] v 24 )
    : *u64 p ( vec_data [u64] v )
    = . p 0 # u64 1 = . p 1 # u64 32898 = . p 2 # u64 -9223372036854742902 = . p 3 # u64 -9223372034707259392
    = . p 4 # u64 32907 = . p 5 # u64 2147483649 = . p 6 # u64 -9223372034707259263 = . p 7 # u64 -9223372036854743031
    = . p 8 # u64 138 = . p 9 # u64 136 = . p 10 # u64 2147516425 = . p 11 # u64 2147483658
    = . p 12 # u64 2147516555 = . p 13 # u64 -9223372036854775669 = . p 14 # u64 -9223372036854742903 = . p 15 # u64 -9223372036854743037
    = . p 16 # u64 -9223372036854743038 = . p 17 # u64 -9223372036854775680 = . p 18 # u64 32778 = . p 19 # u64 -9223372034707292150
    = . p 20 # u64 -9223372034707259263 = . p 21 # u64 -9223372036854742912 = . p 22 # u64 2147483649 = . p 23 # u64 -9223372034707259384
    ^ v
}

// The permutation, in place over 25 lanes.
//
// θ's D-values are folded straight into ρ+π rather than written back to
// the state first: b[dst] = rotl(a[src] ^ d[src mod 5], r[src]) does in
// one pass what the spec describes as two. The 25 lanes are held in
// named locals across the round so the whole body stays in registers —
// spelled as loops over the state array instead, every lane would be
// re-loaded three times a round, 24 rounds deep, for a permutation that
// is otherwise pure ALU.
@ __keccakf1600 * u64 a * u64 rc → v {
    : ~ i rnd 0
    ~ < rnd 24 {
        // θ — column parities
        : u64 c0 ^^ ^^ ^^ ^^ . a 0 . a 5 . a 10 . a 15 . a 20
        : u64 c1 ^^ ^^ ^^ ^^ . a 1 . a 6 . a 11 . a 16 . a 21
        : u64 c2 ^^ ^^ ^^ ^^ . a 2 . a 7 . a 12 . a 17 . a 22
        : u64 c3 ^^ ^^ ^^ ^^ . a 3 . a 8 . a 13 . a 18 . a 23
        : u64 c4 ^^ ^^ ^^ ^^ . a 4 . a 9 . a 14 . a 19 . a 24
        : u64 d0 ^^ c4 ( __k_rotl c1 1 )
        : u64 d1 ^^ c0 ( __k_rotl c2 1 )
        : u64 d2 ^^ c1 ( __k_rotl c3 1 )
        : u64 d3 ^^ c2 ( __k_rotl c4 1 )
        : u64 d4 ^^ c3 ( __k_rotl c0 1 )

        // ρ + π, with θ applied on the way in
        : u64 b0 ^^ . a 0 d0
        : u64 b1 ( __k_rotl ^^ . a 6 d1 44 )
        : u64 b2 ( __k_rotl ^^ . a 12 d2 43 )
        : u64 b3 ( __k_rotl ^^ . a 18 d3 21 )
        : u64 b4 ( __k_rotl ^^ . a 24 d4 14 )
        : u64 b5 ( __k_rotl ^^ . a 3 d3 28 )
        : u64 b6 ( __k_rotl ^^ . a 9 d4 20 )
        : u64 b7 ( __k_rotl ^^ . a 10 d0 3 )
        : u64 b8 ( __k_rotl ^^ . a 16 d1 45 )
        : u64 b9 ( __k_rotl ^^ . a 22 d2 61 )
        : u64 b10 ( __k_rotl ^^ . a 1 d1 1 )
        : u64 b11 ( __k_rotl ^^ . a 7 d2 6 )
        : u64 b12 ( __k_rotl ^^ . a 13 d3 25 )
        : u64 b13 ( __k_rotl ^^ . a 19 d4 8 )
        : u64 b14 ( __k_rotl ^^ . a 20 d0 18 )
        : u64 b15 ( __k_rotl ^^ . a 4 d4 27 )
        : u64 b16 ( __k_rotl ^^ . a 5 d0 36 )
        : u64 b17 ( __k_rotl ^^ . a 11 d1 10 )
        : u64 b18 ( __k_rotl ^^ . a 17 d2 15 )
        : u64 b19 ( __k_rotl ^^ . a 23 d3 56 )
        : u64 b20 ( __k_rotl ^^ . a 2 d2 62 )
        : u64 b21 ( __k_rotl ^^ . a 8 d3 55 )
        : u64 b22 ( __k_rotl ^^ . a 14 d4 39 )
        : u64 b23 ( __k_rotl ^^ . a 15 d0 41 )
        : u64 b24 ( __k_rotl ^^ . a 21 d1 2 )

        // χ — row-wise, then ι on lane 0
        = . a 0 ^^ ^^ b0 & ~ b1 b2 . rc rnd
        = . a 1 ^^ b1 & ~ b2 b3
        = . a 2 ^^ b2 & ~ b3 b4
        = . a 3 ^^ b3 & ~ b4 b0
        = . a 4 ^^ b4 & ~ b0 b1
        = . a 5 ^^ b5 & ~ b6 b7
        = . a 6 ^^ b6 & ~ b7 b8
        = . a 7 ^^ b7 & ~ b8 b9
        = . a 8 ^^ b8 & ~ b9 b5
        = . a 9 ^^ b9 & ~ b5 b6
        = . a 10 ^^ b10 & ~ b11 b12
        = . a 11 ^^ b11 & ~ b12 b13
        = . a 12 ^^ b12 & ~ b13 b14
        = . a 13 ^^ b13 & ~ b14 b10
        = . a 14 ^^ b14 & ~ b10 b11
        = . a 15 ^^ b15 & ~ b16 b17
        = . a 16 ^^ b16 & ~ b17 b18
        = . a 17 ^^ b17 & ~ b18 b19
        = . a 18 ^^ b18 & ~ b19 b15
        = . a 19 ^^ b19 & ~ b15 b16
        = . a 20 ^^ b20 & ~ b21 b22
        = . a 21 ^^ b21 & ~ b22 b23
        = . a 22 ^^ b22 & ~ b23 b24
        = . a 23 ^^ b23 & ~ b24 b20
        = . a 24 ^^ b24 & ~ b20 b21

        = rnd + rnd 1
    }
}

// ── The sponge ─────────────────────────────────────────────────────

: Sha3 {
    ( Vec u64 ) st  // 25 lanes
    ( Vec u64 ) rc  // ι constants
    i rate  // bytes absorbed/squeezed per permutation
    i pos  // byte offset into the current block
    i dom  // domain-separation byte: 6 for SHA-3, 31 for SHAKE
    b squeezing  // T once pad10*1 has been applied
}

// A sponge with an explicit rate and domain byte. `rate` is the block
// size in bytes (200 - 2·capacity/8); `dom` is 6 for the SHA-3 digests
// and 31 for the SHAKE XOFs.
@ sha3_new i rate i dom → *Sha3 {
    : *Sha3 h # *Sha3 ( nurl_alloc Z Sha3 )
    : ( Vec u64 ) st ( vec_with_cap [u64] 25 )
    : b _l ( vec_set_len [u64] st 25 )
    : *u64 sp ( vec_data [u64] st )
    : ~ i i 0
    ~ < i 25 { = . sp i # u64 0 = i + i 1 }
    = . h st st
    = . h rc ( __keccak_rc )
    = . h rate rate
    = . h pos 0
    = . h dom dom
    = . h squeezing F
    ^ h
}

@ sha3_free * Sha3 h → v {
    ( vec_free [u64] . h st )
    ( vec_free [u64] . h rc )
    ( nurl_free # s h )
}

// XOR `n` bytes at `p` into the state at byte offset `pos`, permuting
// whenever a full rate block has gone in.
//
// Whole lanes go in eight bytes at a time: a rate block is 168 bytes for
// SHAKE128, and folding those one byte at a time costs a load, a shift,
// an or and a store apiece for what is one aligned XOR per lane. The
// byte loops on either side handle only the unaligned head and the
// ragged tail.
@ __sha3_absorb_raw * Sha3 h * u p i n → v {
    : *u64 sp ( vec_data [u64] . h st )
    : i rate . h rate
    : ~ i off 0
    : ~ i pos . h pos
    ~ < off n {
        ? & == % pos 8 0 & <= + pos 8 rate <= + off 8 n {
            // aligned whole lane
            : u64 w | | | | | | |
            # u64 . p off
            << # u64 . p + off 1 # u64 8
            << # u64 . p + off 2 # u64 16
            << # u64 . p + off 3 # u64 24
            << # u64 . p + off 4 # u64 32
            << # u64 . p + off 5 # u64 40
            << # u64 . p + off 6 # u64 48
            << # u64 . p + off 7 # u64 56
            : i lane / pos 8
            = . sp lane ^^ . sp lane w
            = off + off 8
            = pos + pos 8
        } {
            : i lane / pos 8
            : i sh * 8 % pos 8
            = . sp lane ^^ . sp lane << # u64 . p off # u64 sh
            = off + off 1
            = pos + pos 1
        }
        ? >= pos rate {
            ( __keccakf1600 sp ( vec_data [u64] . h rc ) )
            = pos 0
        } {}
    }
    = . h pos pos
}

@ sha3_absorb * Sha3 h ( Vec u ) data → v {
    ? . h squeezing { ^ v } {}
    : i n ( vec_len [u] data )
    ? <= n 0 { ^ v } {}
    ( __sha3_absorb_raw h ( vec_data [u] data ) n )
}

// pad10*1 with the domain byte, then permute so the first squeeze reads
// a fresh block.
@ __sha3_pad * Sha3 h → v {
    ? . h squeezing { ^ v } {}
    : *u64 sp ( vec_data [u64] . h st )
    : i pos . h pos
    : i rate . h rate
    = . sp / pos 8 ^^ . sp / pos 8 << # u64 . h dom # u64 * 8 % pos 8
    : i last - rate 1
    = . sp / last 8 ^^ . sp / last 8 << # u64 128 # u64 * 8 % last 8
    ( __keccakf1600 sp ( vec_data [u64] . h rc ) )
    = . h pos 0
    = . h squeezing T
}

// Pull `n` more bytes out of the sponge. Repeated calls continue the
// same stream, so ( squeeze h 3 ) three times and ( squeeze h 9 ) once
// return the same nine bytes — the property ML-KEM's rejection sampler
// depends on.
@ sha3_squeeze * Sha3 h i n → ( Vec u ) {
    ? ! . h squeezing { ( __sha3_pad h ) } {}
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    ? <= n 0 { ^ out } {}
    : b _l ( vec_set_len [u] out n )
    : *u op ( vec_data [u] out )
    : *u64 sp ( vec_data [u64] . h st )
    : i rate . h rate
    : ~ i off 0
    : ~ i pos . h pos
    ~ < off n {
        ? >= pos rate {
            ( __keccakf1600 sp ( vec_data [u64] . h rc ) )
            = pos 0
        } {}
        ? & == % pos 8 0 & <= + pos 8 rate <= + off 8 n {
            : u64 w . sp / pos 8
            = . op off # u & # i w 255
            = . op + off 1 # u & # i >> w # u64 8 255
            = . op + off 2 # u & # i >> w # u64 16 255
            = . op + off 3 # u & # i >> w # u64 24 255
            = . op + off 4 # u & # i >> w # u64 32 255
            = . op + off 5 # u & # i >> w # u64 40 255
            = . op + off 6 # u & # i >> w # u64 48 255
            = . op + off 7 # u & # i >> w # u64 56 255
            = off + off 8
            = pos + pos 8
        } {
            : u64 w . sp / pos 8
            = . op off # u & # i >> w # u64 * 8 % pos 8 255
            = off + off 1
            = pos + pos 1
        }
    }
    = . h pos pos
    ^ out
}

// ── One-shot entries ───────────────────────────────────────────────

@ __sha3_oneshot ( Vec u ) data i rate i dom i outlen → ( Vec u ) {
    : *Sha3 h ( sha3_new rate dom )
    ( sha3_absorb h data )
    : ( Vec u ) out ( sha3_squeeze h outlen )
    ( sha3_free h )
    ^ out
}

@ sha3_224_pure ( Vec u ) data → ( Vec u ) { ^ ( __sha3_oneshot data 144 6 28 ) }

@ sha3_256_pure ( Vec u ) data → ( Vec u ) { ^ ( __sha3_oneshot data 136 6 32 ) }

@ sha3_384_pure ( Vec u ) data → ( Vec u ) { ^ ( __sha3_oneshot data 104 6 48 ) }

@ sha3_512_pure ( Vec u ) data → ( Vec u ) { ^ ( __sha3_oneshot data 72 6 64 ) }

@ shake128_pure ( Vec u ) data i outlen → ( Vec u ) { ^ ( __sha3_oneshot data 168 31 outlen ) }

@ shake256_pure ( Vec u ) data i outlen → ( Vec u ) { ^ ( __sha3_oneshot data 136 31 outlen ) }

@ shake128_init → *Sha3 { ^ ( sha3_new 168 31 ) }

@ shake256_init → *Sha3 { ^ ( sha3_new 136 31 ) }
