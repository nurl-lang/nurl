// stdlib/std/hash_sha3x4.nu — four Keccak sponges at once, on v256.
//
// Keccak is not a bottleneck the way a slow loop is a bottleneck. It is
// 34-40% of ML-KEM and ML-DSA and essentially ALL of SLH-DSA, and the
// permutation is already tight — measured against pq-crystals' own
// reference C on the same host, stdlib's scalar Keccak is the faster of
// the two. What separates it from a production implementation is not
// how the permutation is written but HOW MANY run at a time.
//
// Every post-quantum scheme in the tree hands SHAKE four independent
// jobs at once and waits for all four:
//
//   ML-KEM  matrix A       k*k independent SHAKE128 streams from
//                          rho || j || i
//   ML-DSA  ExpandA/ExpandS same shape, over a k*l matrix
//   SLH-DSA WOTS+ / FORS   whole subtrees of independent leaf chains
//
// Four 64-bit lanes is one 256-bit register, so four sponges advance in
// lockstep for the instruction count of one. That is the entire content
// of the AVX2 speedup those schemes are measured against: on this host,
// SPHINCS+'s AVX2 build generates FOUR WOTS+ public keys in the time its
// reference C generates one (542 us vs 562 us) — 4.1x, from nothing but
// running four states side by side.
//
// State layout is the interleave that makes that work: 25 lanes of four
// ways, way W of lane L at u64 index L*4 + W, so lane L of all four
// sponges is one aligned 32-byte v256 load. The four sponges are
// INDEPENDENT — nothing crosses lanes, ever — which is also why the
// differential gate below can check this against the scalar sponge one
// way at a time.
//
// API — mirrors stdlib/std/hash_sha3.nu, four at a time:
//
//   ( shake128x4_init )                  → *Sha3x4    rate 168
//   ( shake256x4_init )                  → *Sha3x4    rate 136
//   ( sha3x4_new i rate i dom )          → *Sha3x4
//   ( sha3x4_absorb h d0 d1 d2 d3 )      → v
//   ( sha3x4_squeeze h n o0 o1 o2 o3 )   → v
//   ( sha3x4_free h )                    → v
//
// The four inputs to one `sha3x4_absorb` must be THE SAME LENGTH, and
// the four outputs of one `sha3x4_squeeze` are the same length too.
// That is not a simplification — it is what every caller above wants:
// the seeds differ only in a domain index appended to a shared prefix.
// A caller whose lanes need different amounts (ML-KEM's rejection
// sampler consumes a different number of bytes per coefficient stream)
// squeezes a block for all four and lets each lane take what it needs.
// Absorbing unequal lengths is a programming error; the call is
// ignored, exactly as absorbing after squeezing is.
//
// Squeeze writes into caller-supplied buffers rather than returning
// four vectors: four allocations per block, in the middle of the one
// loop this file exists to speed up, is the cost the interleave was
// meant to avoid.

$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_sha3.nu`

// ── The permutation, four ways ─────────────────────────────────────
//
// A lane-for-lane transcription of __keccakf1600, including its
// ping-pong buffer: the register-pressure argument that motivated the
// second buffer is if anything stronger here, because AVX2 has 16
// vector registers and the naive shape wants 35 values live.
//
// The `simd` prefix (docs/spec.md §3.3b) is what makes this worth
// writing. Without it nurlc compiles for baseline x86-64, where LLVM
// legalises every <4 x i64> into a pair of SSE2 operations — correct,
// and about as fast as the scalar sponge, i.e. pointless. With it the
// wide clone gets real vpxor / vpsllq / vpandn and the baseline clone
// stays behind for machines that need it.

@ __k4_ld * u64 p i lane → v256 { ^ ( nurl_v256_ld # s + # i p * lane 32 ) }

@ __k4_st * u64 p i lane v256 v → v { ( nurl_v256_st # s + # i p * lane 32 v ) }

@ __k4_x5 v256 a v256 b v256 c v256 d v256 e → v256 {
    ^ ( nurl_v256_xor
    ( nurl_v256_xor ( nurl_v256_xor a b ) ( nurl_v256_xor c d ) ) e )
}

// theta's D folded into rho: rotl(s[i] ^ d, r), the same one-pass shape
// the scalar permutation uses.
@ __k4_rd v256 s v256 d i r → v256 {
    ^ ( nurl_v256_rotl64 ( nurl_v256_xor s d ) r )
}

// chi: a ^ (~b & c). One vpandn and one vpxor.
@ __k4_chi v256 a v256 b v256 c → v256 {
    ^ ( nurl_v256_xor a ( nurl_v256_andnot b c ) )
}

simd @ __kf1600x4 * u64 a * u64 b * u64 rc → v {
    : ~ i rnd 0
    ~ < rnd 24 {
        : b even == % rnd 2 0
        : *u64 s ? even a b
        : *u64 o ? even b a

        : v256 c0 ( __k4_x5 ( __k4_ld s 0 ) ( __k4_ld s 5 ) ( __k4_ld s 10 ) ( __k4_ld s 15 ) ( __k4_ld s 20 ) )
        : v256 c1 ( __k4_x5 ( __k4_ld s 1 ) ( __k4_ld s 6 ) ( __k4_ld s 11 ) ( __k4_ld s 16 ) ( __k4_ld s 21 ) )
        : v256 c2 ( __k4_x5 ( __k4_ld s 2 ) ( __k4_ld s 7 ) ( __k4_ld s 12 ) ( __k4_ld s 17 ) ( __k4_ld s 22 ) )
        : v256 c3 ( __k4_x5 ( __k4_ld s 3 ) ( __k4_ld s 8 ) ( __k4_ld s 13 ) ( __k4_ld s 18 ) ( __k4_ld s 23 ) )
        : v256 c4 ( __k4_x5 ( __k4_ld s 4 ) ( __k4_ld s 9 ) ( __k4_ld s 14 ) ( __k4_ld s 19 ) ( __k4_ld s 24 ) )
        : v256 d0 ( nurl_v256_xor c4 ( nurl_v256_rotl64 c1 1 ) )
        : v256 d1 ( nurl_v256_xor c0 ( nurl_v256_rotl64 c2 1 ) )
        : v256 d2 ( nurl_v256_xor c1 ( nurl_v256_rotl64 c3 1 ) )
        : v256 d3 ( nurl_v256_xor c2 ( nurl_v256_rotl64 c4 1 ) )
        : v256 d4 ( nurl_v256_xor c3 ( nurl_v256_rotl64 c0 1 ) )

        // Row 0 ← lanes 0, 6, 12, 18, 24
        : v256 r00 ( nurl_v256_xor ( __k4_ld s 0 ) d0 )
        : v256 r01 ( __k4_rd ( __k4_ld s 6 ) d1 44 )
        : v256 r02 ( __k4_rd ( __k4_ld s 12 ) d2 43 )
        : v256 r03 ( __k4_rd ( __k4_ld s 18 ) d3 21 )
        : v256 r04 ( __k4_rd ( __k4_ld s 24 ) d4 14 )
        // iota goes into lane 0 of every way, so the constant is a
        // broadcast — the one place the four sponges see the same bits.
        ( __k4_st o 0 ( nurl_v256_xor ( __k4_chi r00 r01 r02 )
        ( nurl_v256_bcast64 # i . rc rnd ) ) )
        ( __k4_st o 1 ( __k4_chi r01 r02 r03 ) )
        ( __k4_st o 2 ( __k4_chi r02 r03 r04 ) )
        ( __k4_st o 3 ( __k4_chi r03 r04 r00 ) )
        ( __k4_st o 4 ( __k4_chi r04 r00 r01 ) )

        // Row 1 ← lanes 3, 9, 10, 16, 22
        : v256 r10 ( __k4_rd ( __k4_ld s 3 ) d3 28 )
        : v256 r11 ( __k4_rd ( __k4_ld s 9 ) d4 20 )
        : v256 r12 ( __k4_rd ( __k4_ld s 10 ) d0 3 )
        : v256 r13 ( __k4_rd ( __k4_ld s 16 ) d1 45 )
        : v256 r14 ( __k4_rd ( __k4_ld s 22 ) d2 61 )
        ( __k4_st o 5 ( __k4_chi r10 r11 r12 ) )
        ( __k4_st o 6 ( __k4_chi r11 r12 r13 ) )
        ( __k4_st o 7 ( __k4_chi r12 r13 r14 ) )
        ( __k4_st o 8 ( __k4_chi r13 r14 r10 ) )
        ( __k4_st o 9 ( __k4_chi r14 r10 r11 ) )

        // Row 2 ← lanes 1, 7, 13, 19, 20
        : v256 r20 ( __k4_rd ( __k4_ld s 1 ) d1 1 )
        : v256 r21 ( __k4_rd ( __k4_ld s 7 ) d2 6 )
        : v256 r22 ( __k4_rd ( __k4_ld s 13 ) d3 25 )
        : v256 r23 ( __k4_rd ( __k4_ld s 19 ) d4 8 )
        : v256 r24 ( __k4_rd ( __k4_ld s 20 ) d0 18 )
        ( __k4_st o 10 ( __k4_chi r20 r21 r22 ) )
        ( __k4_st o 11 ( __k4_chi r21 r22 r23 ) )
        ( __k4_st o 12 ( __k4_chi r22 r23 r24 ) )
        ( __k4_st o 13 ( __k4_chi r23 r24 r20 ) )
        ( __k4_st o 14 ( __k4_chi r24 r20 r21 ) )

        // Row 3 ← lanes 4, 5, 11, 17, 23
        : v256 r30 ( __k4_rd ( __k4_ld s 4 ) d4 27 )
        : v256 r31 ( __k4_rd ( __k4_ld s 5 ) d0 36 )
        : v256 r32 ( __k4_rd ( __k4_ld s 11 ) d1 10 )
        : v256 r33 ( __k4_rd ( __k4_ld s 17 ) d2 15 )
        : v256 r34 ( __k4_rd ( __k4_ld s 23 ) d3 56 )
        ( __k4_st o 15 ( __k4_chi r30 r31 r32 ) )
        ( __k4_st o 16 ( __k4_chi r31 r32 r33 ) )
        ( __k4_st o 17 ( __k4_chi r32 r33 r34 ) )
        ( __k4_st o 18 ( __k4_chi r33 r34 r30 ) )
        ( __k4_st o 19 ( __k4_chi r34 r30 r31 ) )

        // Row 4 ← lanes 2, 8, 14, 15, 21
        : v256 r40 ( __k4_rd ( __k4_ld s 2 ) d2 62 )
        : v256 r41 ( __k4_rd ( __k4_ld s 8 ) d3 55 )
        : v256 r42 ( __k4_rd ( __k4_ld s 14 ) d4 39 )
        : v256 r43 ( __k4_rd ( __k4_ld s 15 ) d0 41 )
        : v256 r44 ( __k4_rd ( __k4_ld s 21 ) d1 2 )
        ( __k4_st o 20 ( __k4_chi r40 r41 r42 ) )
        ( __k4_st o 21 ( __k4_chi r41 r42 r43 ) )
        ( __k4_st o 22 ( __k4_chi r42 r43 r44 ) )
        ( __k4_st o 23 ( __k4_chi r43 r44 r40 ) )
        ( __k4_st o 24 ( __k4_chi r44 r40 r41 ) )

        = rnd + rnd 1
    }
}

// ── The four-way sponge ────────────────────────────────────────────

: Sha3x4 {
    ( Vec u64 ) st  // 25 lanes x 4 ways, way W of lane L at L*4 + W
    ( Vec u64 ) scr  // 100-lane ping-pong buffer
    ( Vec u64 ) rc  // the 24 iota constants, shared by all four
    i rate  // bytes per permutation, per way
    i pos  // byte offset into the current block — the SAME for all four
    i dom  // domain byte: 6 for SHA-3, 31 for SHAKE
    b squeezing
}

@ sha3x4_new i rate i dom → *Sha3x4 {
    : *Sha3x4 h # *Sha3x4 ( nurl_alloc Z Sha3x4 )
    : ( Vec u64 ) st ( vec_with_cap [u64] 100 )
    : b _l ( vec_set_len [u64] st 100 )
    : *u64 sp ( vec_data [u64] st )
    : ~ i i 0
    ~ < i 100 { = . sp i # u64 0 = i + i 1 }
    = . h st st
    : ( Vec u64 ) scr ( vec_with_cap [u64] 100 )
    : b _l2 ( vec_set_len [u64] scr 100 )
    = . h scr scr
    = . h rc ( keccak_round_constants )
    = . h rate rate
    = . h pos 0
    = . h dom dom
    = . h squeezing F
    ^ h
}

@ sha3x4_free * Sha3x4 h → v {
    ( vec_free [u64] . h st )
    ( vec_free [u64] . h scr )
    ( vec_free [u64] . h rc )
    ( nurl_free # s h )
}

@ shake128x4_init → *Sha3x4 { ^ ( sha3x4_new 168 31 ) }

@ shake256x4_init → *Sha3x4 { ^ ( sha3x4_new 136 31 ) }

// XOR one byte into way `w` at block offset `pos`. The interleave puts
// way w of lane L at u64 index L*4 + w, so the byte's home is decided
// by pos exactly as in the scalar sponge and then shifted four over.
@ __k4_absorb_byte * u64 sp i w i pos i byte → v {
    : i idx + * 4 / pos 8 w
    = . sp idx ^^ . sp idx << # u64 byte # u64 * 8 % pos 8
}

// The whole-lane case: eight input bytes become one little-endian u64
// XORed into way `w` of lane `lane`.
@ __k4_in8 * u64 sp i lane i w * u p i off → v {
    : u64 x | | | | | | |
    # u64 # i . p off
    << # u64 # i . p + off 1 # u64 8
    << # u64 # i . p + off 2 # u64 16
    << # u64 # i . p + off 3 # u64 24
    << # u64 # i . p + off 4 # u64 32
    << # u64 # i . p + off 5 # u64 40
    << # u64 # i . p + off 6 # u64 48
    << # u64 # i . p + off 7 # u64 56
    : i idx + * 4 lane w
    = . sp idx ^^ . sp idx x
}

@ __k4_permute * Sha3x4 h → v {
    ( __kf1600x4 ( vec_data [u64] . h st ) ( vec_data [u64] . h scr )
    ( vec_data [u64] . h rc ) )
}

// Absorb one same-length piece into each of the four sponges.
//
// Byte-at-a-time rather than the scalar sponge's 8-bytes-at-a-time fast
// path: absorption is a vanishing fraction of the work here (a PQ seed
// is 32-66 bytes against 24 rounds of permutation per 168-byte block),
// and four interleaved ways make the aligned case rarer than it looks.
// Correctness first where it costs nothing.
@ sha3x4_absorb * Sha3x4 h ( Vec u ) d0 ( Vec u ) d1 ( Vec u ) d2 ( Vec u ) d3 → v {
    ? . h squeezing { ^ v } {}
    : i n ( vec_len [u] d0 )
    // Equal lengths are the contract. Silently absorbing the shortest
    // would produce four sponges in different states from a call that
    // looked like it succeeded.
    ? ! & & == n ( vec_len [u] d1 ) == n ( vec_len [u] d2 ) == n ( vec_len [u] d3 )
    { ^ v } {}
    ? <= n 0 { ^ v } {}
    : *u p0 ( vec_data [u] d0 )
    : *u p1 ( vec_data [u] d1 )
    : *u p2 ( vec_data [u] d2 )
    : *u p3 ( vec_data [u] d3 )
    : *u64 sp ( vec_data [u64] . h st )
    : i rate . h rate
    : ~ i pos . h pos
    : ~ i off 0
    ~ < off n {
        ? & & == % pos 8 0 <= + pos 8 rate <= + off 8 n {
            : i lane / pos 8
            ( __k4_in8 sp lane 0 p0 off )
            ( __k4_in8 sp lane 1 p1 off )
            ( __k4_in8 sp lane 2 p2 off )
            ( __k4_in8 sp lane 3 p3 off )
            = off + off 8
            = pos + pos 8
        } {
            ( __k4_absorb_byte sp 0 pos # i . p0 off )
            ( __k4_absorb_byte sp 1 pos # i . p1 off )
            ( __k4_absorb_byte sp 2 pos # i . p2 off )
            ( __k4_absorb_byte sp 3 pos # i . p3 off )
            = off + off 1
            = pos + pos 1
        }
        ? >= pos rate { ( __k4_permute h ) = pos 0 } {}
    }
    = . h pos pos
}

// pad10*1 with the domain byte, in all four ways at once.
@ __k4_pad * Sha3x4 h → v {
    ? . h squeezing { ^ v } {}
    : *u64 sp ( vec_data [u64] . h st )
    : i pos . h pos
    : i last - . h rate 1
    : ~ i w 0
    ~ < w 4 {
        ( __k4_absorb_byte sp w pos . h dom )
        ( __k4_absorb_byte sp w last 128 )
        = w + w 1
    }
    ( __k4_permute h )
    = . h pos 0
    = . h squeezing T
}

// Pull `n` more bytes out of each sponge, appending to o0..o3.
// Repeated calls continue the same four streams, which is what a
// rejection sampler needs.
//
// Eight bytes at a time whenever the block and the request both allow
// it, and straight into the vectors' storage rather than through
// vec_push. That is not a micro-optimisation here: the first version of
// this function pushed one byte per lane per iteration and the profile
// came back with the SPONGE at 55% and the permutation — the whole
// point of the file — at 28%, so a permutation running 4x faster per
// stream turned into 1.11x end to end. Squeezing 504 bytes is 2016
// pushes against three permutations; the plumbing has to be as wide as
// the thing it is plumbing.
@ __k4_out8 * u p i off u64 w → v {
    = . p off # u & # i w 255
    = . p + off 1 # u & # i >> w # u64 8 255
    = . p + off 2 # u & # i >> w # u64 16 255
    = . p + off 3 # u & # i >> w # u64 24 255
    = . p + off 4 # u & # i >> w # u64 32 255
    = . p + off 5 # u & # i >> w # u64 40 255
    = . p + off 6 # u & # i >> w # u64 48 255
    = . p + off 7 # u & # i >> w # u64 56 255
}

@ sha3x4_squeeze * Sha3x4 h i n ( Vec u ) o0 ( Vec u ) o1 ( Vec u ) o2 ( Vec u ) o3 → v {
    ? ! . h squeezing { ( __k4_pad h ) } {}
    ? <= n 0 { ^ v } {}
    // Grow all four to their final length up front, then write through
    // the raw pointers. vec_data is only valid until the next growth,
    // so every reallocation has to happen before the loop starts.
    : i b0 ( vec_len [u] o0 )
    : i b1 ( vec_len [u] o1 )
    : i b2 ( vec_len [u] o2 )
    : i b3 ( vec_len [u] o3 )
    ( vec_reserve [u] o0 n ) ( vec_reserve [u] o1 n )
    ( vec_reserve [u] o2 n ) ( vec_reserve [u] o3 n )
    : b l0 ( vec_set_len [u] o0 + b0 n )
    : b l1 ( vec_set_len [u] o1 + b1 n )
    : b l2 ( vec_set_len [u] o2 + b2 n )
    : b l3 ( vec_set_len [u] o3 + b3 n )
    ? ! & & & l0 l1 l2 l3 { ^ v } {}
    : *u p0 ( vec_data [u] o0 )
    : *u p1 ( vec_data [u] o1 )
    : *u p2 ( vec_data [u] o2 )
    : *u p3 ( vec_data [u] o3 )
    : *u64 sp ( vec_data [u64] . h st )
    : i rate . h rate
    : ~ i pos . h pos
    : ~ i off 0
    ~ < off n {
        ? >= pos rate { ( __k4_permute h ) = pos 0 } {}
        : i lane / pos 8
        ? & == % pos 8 0 & <= + pos 8 rate <= + off 8 n {
            ( __k4_out8 p0 + b0 off . sp + * 4 lane 0 )
            ( __k4_out8 p1 + b1 off . sp + * 4 lane 1 )
            ( __k4_out8 p2 + b2 off . sp + * 4 lane 2 )
            ( __k4_out8 p3 + b3 off . sp + * 4 lane 3 )
            = off + off 8
            = pos + pos 8
        } {
            : i sh * 8 % pos 8
            = . p0 + b0 off # u & # i >> . sp + * 4 lane 0 # u64 sh 255
            = . p1 + b1 off # u & # i >> . sp + * 4 lane 1 # u64 sh 255
            = . p2 + b2 off # u & # i >> . sp + * 4 lane 2 # u64 sh 255
            = . p3 + b3 off # u & # i >> . sp + * 4 lane 3 # u64 sh 255
            = off + off 1
            = pos + pos 1
        }
    }
    = . h pos pos
}
