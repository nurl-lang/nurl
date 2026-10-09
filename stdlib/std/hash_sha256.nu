// stdlib/std/hash_sha256.nu — FIPS 180-4 SHA-256 in pure NURL.
//
// API:
//   ( sha256_pure ( Vec u ) data )       → ( Vec u )   32-byte digest
//   ( hmac_sha256_pure ( Vec u ) key
//                       ( Vec u ) msg )   → ( Vec u )   32-byte HMAC
//   ( sha256_init ) → Sha256, sha256_update / _final / _snapshot — the
//   streaming core below; the handle releases itself.

$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/bytes.nu`

// Right-rotate u32 by c bits (0 < c < 32).
//
// `nurl_rotr32` is the compiler's funnel-shift primitive: one `ror`
// instruction on every ISA that has one. Spelled as the shift pair and
// the `or` it replaces, the two shifts also had to be materialised as
// 32-bit values first, and the six rotations a SHA-256 round performs
// each paid for that. This routine runs 64 times per 64-byte block, on
// every transcript hash, every HKDF expansion and every HMAC of the TLS
// handshake.
@ __sha256_rotr u32 x i c → u32 {
    ^ # u32 ( nurl_rotr32 # u64 x # u64 c )
}

// ── 64-entry round-constant table per FIPS 180-4 §4.2.2 ────────────

// One process-wide copy of the round-constant table, built on first use
// and BORROWED by every handle: the table is a public constant, and a TLS
// key schedule runs one `sha256_init` per HMAC leg — a 64-word build and
// a heap alloc/free per digest bought nothing. Two first callers may both
// build: the runtime's publish-once slot 3 picks one, and the other copy
// is dropped (stdlib/std/tls_server.nu keeps the slot registry).
: ~ i g_sha256_k 0

& `c` @ nurl_once_slot i id i candidate → i

@ __sha256_k_shared → ( Vec u32 ) {
    ? == g_sha256_k 0 {
        : ( Vec u32 ) k ( __sha256_K )
        : i won ( nurl_once_slot 3 # i . k ctl )
        // The winner lives for the rest of the program, through the global.
        ? == won # i . k ctl { ( mem_forget k ) } {}
        = g_sha256_k won
    } {}
    ^ @ ( Vec u32 ) { # s g_sha256_k }
}

@ __sha256_K → ( Vec u32 ) {
    // Filled by index through a raw `*u32`.
    : ( Vec u32 ) k ( vec_with_cap [u32] 64 )
    : b _l ( vec_set_len [u32] k 64 )
    : *u32 kp ( vec_data [u32] k )
    = . kp 0 # u32 1116352408 = . kp 1 # u32 1899447441 = . kp 2 # u32 3049323471 = . kp 3 # u32 3921009573
    = . kp 4 # u32 961987163 = . kp 5 # u32 1508970993 = . kp 6 # u32 2453635748 = . kp 7 # u32 2870763221
    = . kp 8 # u32 3624381080 = . kp 9 # u32 310598401 = . kp 10 # u32 607225278 = . kp 11 # u32 1426881987
    = . kp 12 # u32 1925078388 = . kp 13 # u32 2162078206 = . kp 14 # u32 2614888103 = . kp 15 # u32 3248222580
    = . kp 16 # u32 3835390401 = . kp 17 # u32 4022224774 = . kp 18 # u32 264347078 = . kp 19 # u32 604807628
    = . kp 20 # u32 770255983 = . kp 21 # u32 1249150122 = . kp 22 # u32 1555081692 = . kp 23 # u32 1996064986
    = . kp 24 # u32 2554220882 = . kp 25 # u32 2821834349 = . kp 26 # u32 2952996808 = . kp 27 # u32 3210313671
    = . kp 28 # u32 3336571891 = . kp 29 # u32 3584528711 = . kp 30 # u32 113926993 = . kp 31 # u32 338241895
    = . kp 32 # u32 666307205 = . kp 33 # u32 773529912 = . kp 34 # u32 1294757372 = . kp 35 # u32 1396182291
    = . kp 36 # u32 1695183700 = . kp 37 # u32 1986661051 = . kp 38 # u32 2177026350 = . kp 39 # u32 2456956037
    = . kp 40 # u32 2730485921 = . kp 41 # u32 2820302411 = . kp 42 # u32 3259730800 = . kp 43 # u32 3345764771
    = . kp 44 # u32 3516065817 = . kp 45 # u32 3600352804 = . kp 46 # u32 4094571909 = . kp 47 # u32 275423344
    = . kp 48 # u32 430227734 = . kp 49 # u32 506948616 = . kp 50 # u32 659060556 = . kp 51 # u32 883997877
    = . kp 52 # u32 958139571 = . kp 53 # u32 1322822218 = . kp 54 # u32 1537002063 = . kp 55 # u32 1747873779
    = . kp 56 # u32 1955562222 = . kp 57 # u32 2024104815 = . kp 58 # u32 2227730452 = . kp 59 # u32 2361852424
    = . kp 60 # u32 2428436474 = . kp 61 # u32 2756734187 = . kp 62 # u32 3204031479 = . kp 63 # u32 3329325298
    ^ k
}

// ── Transform one 64-byte block. Mutates state (8 × u32) in place.
//
// The block is the 64 bytes at `bp`; the state the eight words at `sp`.
// The eight working variables and the 16-word message schedule are scalar
// locals: each of the 64 rounds is one `inline` call that updates the two
// words a round changes (`inout`), written out with the variables already
// rotated into their roles and the round constant as a literal, so no
// round moves a word or loads a constant. The schedule is FIPS 180-4's
// 16-word ring, expanded in place one word ahead of the round that reads
// it. (`kp` and `mp` — the constant table and a 64-word schedule — are
// what a rolled loop needed; the callers still pass them.)

@ __sha256_be32 * u p i o → u32 {
    ^ | | | << # u32 . p o # u32 24 << # u32 . p + o 1 # u32 16
    << # u32 . p + o 2 # u32 8 # u32 . p + o 3
}

// One round: T1 = h + Σ1(e) + Ch(e, f, g) + k + w, T2 = Σ0(a) + Maj(a, b, c);
// d += T1, h = T1 + T2 — the next round sees h as a, d as e.
inline @ __sha256_rnd u32 a u32 b u32 c inout u32 d u32 e u32 f u32 g inout u32 h u32 k u32 w → v {
    : u32 s1 ^^ ^^ ( __sha256_rotr e 6 ) ( __sha256_rotr e 11 ) ( __sha256_rotr e 25 )
    : u32 ch ^^ g & e ^^ f g
    : u32 t1 + + + + h s1 ch k w
    : u32 s0 ^^ ^^ ( __sha256_rotr a 2 ) ( __sha256_rotr a 13 ) ( __sha256_rotr a 22 )
    : u32 mj ^^ & a b & c ^^ a b
    = d + d t1
    = h + t1 + s0 mj
}

// w[t] = σ1(w[t-2]) + w[t-7] + σ0(w[t-15]) + w[t-16], w[t-16] being the
// ring slot w[t] overwrites.
inline @ __sha256_sch inout u32 w u32 w2 u32 w7 u32 w15 → v {
    : u32 s0 ^^ ^^ ( __sha256_rotr w15 7 ) ( __sha256_rotr w15 18 ) >> w15 # u32 3
    : u32 s1 ^^ ^^ ( __sha256_rotr w2 17 ) ( __sha256_rotr w2 19 ) >> w2 # u32 10
    = w + + + w s1 w7 s0
}

@ __sha256_transform * u32 sp * u bp * u32 kp * u32 mp → v {
    : ~ u32 w0 ( __sha256_be32 bp 0 )
    : ~ u32 w1 ( __sha256_be32 bp 4 )
    : ~ u32 w2 ( __sha256_be32 bp 8 )
    : ~ u32 w3 ( __sha256_be32 bp 12 )
    : ~ u32 w4 ( __sha256_be32 bp 16 )
    : ~ u32 w5 ( __sha256_be32 bp 20 )
    : ~ u32 w6 ( __sha256_be32 bp 24 )
    : ~ u32 w7 ( __sha256_be32 bp 28 )
    : ~ u32 w8 ( __sha256_be32 bp 32 )
    : ~ u32 w9 ( __sha256_be32 bp 36 )
    : ~ u32 w10 ( __sha256_be32 bp 40 )
    : ~ u32 w11 ( __sha256_be32 bp 44 )
    : ~ u32 w12 ( __sha256_be32 bp 48 )
    : ~ u32 w13 ( __sha256_be32 bp 52 )
    : ~ u32 w14 ( __sha256_be32 bp 56 )
    : ~ u32 w15 ( __sha256_be32 bp 60 )

    : ~ u32 a . sp 0
    : ~ u32 b . sp 1
    : ~ u32 c . sp 2
    : ~ u32 d . sp 3
    : ~ u32 e . sp 4
    : ~ u32 f . sp 5
    : ~ u32 g . sp 6
    : ~ u32 h . sp 7

    ( __sha256_rnd a b c d e f g h # u32 1116352408 w0 )
    ( __sha256_rnd h a b c d e f g # u32 1899447441 w1 )
    ( __sha256_rnd g h a b c d e f # u32 3049323471 w2 )
    ( __sha256_rnd f g h a b c d e # u32 3921009573 w3 )
    ( __sha256_rnd e f g h a b c d # u32 961987163 w4 )
    ( __sha256_rnd d e f g h a b c # u32 1508970993 w5 )
    ( __sha256_rnd c d e f g h a b # u32 2453635748 w6 )
    ( __sha256_rnd b c d e f g h a # u32 2870763221 w7 )
    ( __sha256_rnd a b c d e f g h # u32 3624381080 w8 )
    ( __sha256_rnd h a b c d e f g # u32 310598401 w9 )
    ( __sha256_rnd g h a b c d e f # u32 607225278 w10 )
    ( __sha256_rnd f g h a b c d e # u32 1426881987 w11 )
    ( __sha256_rnd e f g h a b c d # u32 1925078388 w12 )
    ( __sha256_rnd d e f g h a b c # u32 2162078206 w13 )
    ( __sha256_rnd c d e f g h a b # u32 2614888103 w14 )
    ( __sha256_rnd b c d e f g h a # u32 3248222580 w15 )
    ( __sha256_sch w0 w14 w9 w1 )
    ( __sha256_rnd a b c d e f g h # u32 3835390401 w0 )
    ( __sha256_sch w1 w15 w10 w2 )
    ( __sha256_rnd h a b c d e f g # u32 4022224774 w1 )
    ( __sha256_sch w2 w0 w11 w3 )
    ( __sha256_rnd g h a b c d e f # u32 264347078 w2 )
    ( __sha256_sch w3 w1 w12 w4 )
    ( __sha256_rnd f g h a b c d e # u32 604807628 w3 )
    ( __sha256_sch w4 w2 w13 w5 )
    ( __sha256_rnd e f g h a b c d # u32 770255983 w4 )
    ( __sha256_sch w5 w3 w14 w6 )
    ( __sha256_rnd d e f g h a b c # u32 1249150122 w5 )
    ( __sha256_sch w6 w4 w15 w7 )
    ( __sha256_rnd c d e f g h a b # u32 1555081692 w6 )
    ( __sha256_sch w7 w5 w0 w8 )
    ( __sha256_rnd b c d e f g h a # u32 1996064986 w7 )
    ( __sha256_sch w8 w6 w1 w9 )
    ( __sha256_rnd a b c d e f g h # u32 2554220882 w8 )
    ( __sha256_sch w9 w7 w2 w10 )
    ( __sha256_rnd h a b c d e f g # u32 2821834349 w9 )
    ( __sha256_sch w10 w8 w3 w11 )
    ( __sha256_rnd g h a b c d e f # u32 2952996808 w10 )
    ( __sha256_sch w11 w9 w4 w12 )
    ( __sha256_rnd f g h a b c d e # u32 3210313671 w11 )
    ( __sha256_sch w12 w10 w5 w13 )
    ( __sha256_rnd e f g h a b c d # u32 3336571891 w12 )
    ( __sha256_sch w13 w11 w6 w14 )
    ( __sha256_rnd d e f g h a b c # u32 3584528711 w13 )
    ( __sha256_sch w14 w12 w7 w15 )
    ( __sha256_rnd c d e f g h a b # u32 113926993 w14 )
    ( __sha256_sch w15 w13 w8 w0 )
    ( __sha256_rnd b c d e f g h a # u32 338241895 w15 )
    ( __sha256_sch w0 w14 w9 w1 )
    ( __sha256_rnd a b c d e f g h # u32 666307205 w0 )
    ( __sha256_sch w1 w15 w10 w2 )
    ( __sha256_rnd h a b c d e f g # u32 773529912 w1 )
    ( __sha256_sch w2 w0 w11 w3 )
    ( __sha256_rnd g h a b c d e f # u32 1294757372 w2 )
    ( __sha256_sch w3 w1 w12 w4 )
    ( __sha256_rnd f g h a b c d e # u32 1396182291 w3 )
    ( __sha256_sch w4 w2 w13 w5 )
    ( __sha256_rnd e f g h a b c d # u32 1695183700 w4 )
    ( __sha256_sch w5 w3 w14 w6 )
    ( __sha256_rnd d e f g h a b c # u32 1986661051 w5 )
    ( __sha256_sch w6 w4 w15 w7 )
    ( __sha256_rnd c d e f g h a b # u32 2177026350 w6 )
    ( __sha256_sch w7 w5 w0 w8 )
    ( __sha256_rnd b c d e f g h a # u32 2456956037 w7 )
    ( __sha256_sch w8 w6 w1 w9 )
    ( __sha256_rnd a b c d e f g h # u32 2730485921 w8 )
    ( __sha256_sch w9 w7 w2 w10 )
    ( __sha256_rnd h a b c d e f g # u32 2820302411 w9 )
    ( __sha256_sch w10 w8 w3 w11 )
    ( __sha256_rnd g h a b c d e f # u32 3259730800 w10 )
    ( __sha256_sch w11 w9 w4 w12 )
    ( __sha256_rnd f g h a b c d e # u32 3345764771 w11 )
    ( __sha256_sch w12 w10 w5 w13 )
    ( __sha256_rnd e f g h a b c d # u32 3516065817 w12 )
    ( __sha256_sch w13 w11 w6 w14 )
    ( __sha256_rnd d e f g h a b c # u32 3600352804 w13 )
    ( __sha256_sch w14 w12 w7 w15 )
    ( __sha256_rnd c d e f g h a b # u32 4094571909 w14 )
    ( __sha256_sch w15 w13 w8 w0 )
    ( __sha256_rnd b c d e f g h a # u32 275423344 w15 )
    ( __sha256_sch w0 w14 w9 w1 )
    ( __sha256_rnd a b c d e f g h # u32 430227734 w0 )
    ( __sha256_sch w1 w15 w10 w2 )
    ( __sha256_rnd h a b c d e f g # u32 506948616 w1 )
    ( __sha256_sch w2 w0 w11 w3 )
    ( __sha256_rnd g h a b c d e f # u32 659060556 w2 )
    ( __sha256_sch w3 w1 w12 w4 )
    ( __sha256_rnd f g h a b c d e # u32 883997877 w3 )
    ( __sha256_sch w4 w2 w13 w5 )
    ( __sha256_rnd e f g h a b c d # u32 958139571 w4 )
    ( __sha256_sch w5 w3 w14 w6 )
    ( __sha256_rnd d e f g h a b c # u32 1322822218 w5 )
    ( __sha256_sch w6 w4 w15 w7 )
    ( __sha256_rnd c d e f g h a b # u32 1537002063 w6 )
    ( __sha256_sch w7 w5 w0 w8 )
    ( __sha256_rnd b c d e f g h a # u32 1747873779 w7 )
    ( __sha256_sch w8 w6 w1 w9 )
    ( __sha256_rnd a b c d e f g h # u32 1955562222 w8 )
    ( __sha256_sch w9 w7 w2 w10 )
    ( __sha256_rnd h a b c d e f g # u32 2024104815 w9 )
    ( __sha256_sch w10 w8 w3 w11 )
    ( __sha256_rnd g h a b c d e f # u32 2227730452 w10 )
    ( __sha256_sch w11 w9 w4 w12 )
    ( __sha256_rnd f g h a b c d e # u32 2361852424 w11 )
    ( __sha256_sch w12 w10 w5 w13 )
    ( __sha256_rnd e f g h a b c d # u32 2428436474 w12 )
    ( __sha256_sch w13 w11 w6 w14 )
    ( __sha256_rnd d e f g h a b c # u32 2756734187 w13 )
    ( __sha256_sch w14 w12 w7 w15 )
    ( __sha256_rnd c d e f g h a b # u32 3204031479 w14 )
    ( __sha256_sch w15 w13 w8 w0 )
    ( __sha256_rnd b c d e f g h a # u32 3329325298 w15 )

    = . sp 0 + . sp 0 a
    = . sp 1 + . sp 1 b
    = . sp 2 + . sp 2 c
    = . sp 3 + . sp 3 d
    = . sp 4 + . sp 4 e
    = . sp 5 + . sp 5 f
    = . sp 6 + . sp 6 g
    = . sp 7 + . sp 7 h
}

// ── Incremental (streaming) hashing ────────────────────────────────
//
// Hash gigabytes without holding them: feed pieces as they arrive
// (file_read_chunk, an HTTP stream) and finalize once. The one-shot
// sha256_pure below is a thin init/update/final composition, so the
// two paths cannot drift.
//
//   ( sha256_init )          → Sha256
//   ( sha256_update h v )    → v          any piece size, any count
//   ( sha256_final h )       → ( Vec u )  32-byte digest; the stream is
//                                          spent after this
//   ( sha256_snapshot h )    → ( Vec u )  digest so far; h keeps absorbing
//
// A Sha256 is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same stream, and the last owner releases it.

// The state behind the handle. All of a stream's scratch is ONE block of
// words, so a stream costs the box and that block — a TLS key schedule
// opens a stream per HMAC, and the three Vecs this used to take (state,
// schedule, partial block: a control block and a buffer each, plus the
// buffer's growth for the padding) were a visible share of a handshake.
// Word offsets into `w`:
//
//   [  0,   8)  chaining state
//   [  8,  16)  a snapshot's copy of the state
//   [ 16,  80)  message schedule
//   [ 80, 112)  partial block, 128 bytes: room for the padding's second block
//   [112, 144)  a snapshot's copy of the partial block
//
// `k` is the process-wide round-constant table (`__sha256_k_shared`),
// borrowed for the program's lifetime and never released.
: Sha256Impl {
    ( Vec u32 ) w
    * u32 k
    i blen  // bytes waiting in the partial block, < 64
    i total  // bytes absorbed so far
}

: Sha256 { s ctl }

@ Sha256_share Sha256 h → Sha256 { ^ @ Sha256 { # s ( rcbox_share # i . h ctl ) } }

@ Sha256_drop sink Sha256 h → v {
    ( mem_forget h )
    ( rcbox_release [Sha256Impl] # i . h ctl )
}

@ __Sha256_ptr Sha256 h → *Sha256Impl { ^ ( rcbox_ptr [Sha256Impl] # i . h ctl ) }

@ sha256_init → Sha256 {
    : ( Vec u32 ) w ( vec_with_cap [u32] 144 )
    : b _l ( vec_set_len [u32] w 144 )
    : *u32 sp ( vec_data [u32] w )
    = . sp 0 # u32 1779033703
    = . sp 1 # u32 3144134277
    = . sp 2 # u32 1013904242
    = . sp 3 # u32 2773480762
    = . sp 4 # u32 1359893119
    = . sp 5 # u32 2600822924
    = . sp 6 # u32 528734635
    = . sp 7 # u32 1541459225
    // Built whole and moved into the box: every field is written, so the
    // block needs no zeroing first.
    ^ @ Sha256 { # s ( rcbox_new [Sha256Impl] @ Sha256Impl { w ( vec_data [u32] ( __sha256_k_shared ) ) 0 0 } ) }
}

// Let go of `h` now rather than at the end of its owner's scope.
@ sha256_free sink Sha256 h → v {}

@ sha256_update Sha256 h__h ( Vec u ) data → v {
    : i n ( vec_len [u] data )
    ? <= n 0 { ^ v } {}
    : *Sha256Impl h ( __Sha256_ptr h__h )
    : *u32 sp ( vec_data [u32] . h w )
    : *u32 kp . h k
    : *u32 mp # *u32 + # i sp 64
    : *u blk # *u + # i sp 320
    : *u dp ( vec_data [u] data )
    = . h total + . h total n
    : ~ i off 0
    // top up a partial block first
    : i have . h blen
    ? > have 0 {
        : i need - 64 have
        : i take ? < n need n need
        ( nurl_memcpy # s + # i blk have # s dp take )
        = off take
        ? == take need {
            ( __sha256_transform sp blk kp mp )
            = . h blen 0
        } { = . h blen + have take }
    } {}
    // full blocks straight from the caller's data — no copy
    ~ <= + off 64 n {
        ( __sha256_transform sp # *u + # i dp off kp mp )
        = off + off 64
    }
    // stash the tail
    ? < off n {
        ( nurl_memcpy # s blk # s + # i dp off - n off )
        = . h blen - n off
    } {}
}

// Pad the `blen` bytes at `blk` (which has room for 128), run the final
// block(s) over the state at `sp`, and serialise it big-endian.
@ __sha256_finish * u32 sp * u blk i blen i total * u32 kp * u32 mp → ( Vec u ) {
    = . blk blen # u 128
    : i end ? <= + blen 1 56 64 128
    : ~ i zi + blen 1
    ~ < zi - end 8 {
        = . blk zi # u 0
        = zi + zi 1
    }
    : i bitlen * total 8
    : ~ i bi 0
    ~ < bi 8 {
        = . blk - - end 1 bi # u & >> bitlen * bi 8 255
        = bi + bi 1
    }
    ( __sha256_transform sp blk kp mp )
    ? == end 128 { ( __sha256_transform sp # *u + # i blk 64 kp mp ) } {}

    : ( Vec u ) out ( vec_with_cap [u] 32 )
    : b _l ( vec_set_len [u] out 32 )
    : *u op ( vec_data [u] out )
    : ~ i si 0
    ~ < si 8 {
        : i siv # i . sp si
        = . op * si 4 # u & >> siv 24 255
        = . op + * si 4 1 # u & >> siv 16 255
        = . op + * si 4 2 # u & >> siv 8 255
        = . op + * si 4 3 # u & siv 255
        = si + si 1
    }
    ^ out
}

// Digest: pads, runs the final block(s) and serialises the state
// big-endian. The stream is spent — its storage goes with its last owner.
@ sha256_final Sha256 h__h → ( Vec u ) {
    : *Sha256Impl h ( __Sha256_ptr h__h )
    : *u32 sp ( vec_data [u32] . h w )
    : ( Vec u ) out ( __sha256_finish sp # *u + # i sp 320 . h blen . h total . h k # *u32 + # i sp 64 )
    = . h blen 0
    ^ out
}

// Digest-so-far WITHOUT consuming the stream: finalises a copy of the
// running state and partial block (the handle's own snapshot area);
// `h` stays live and can keep absorbing. This is what an incremental
// transcript hash needs — TLS 1.3 reads the transcript digest at five
// points while the transcript keeps growing, and re-hashing the whole
// transcript from scratch at each point costs ~5× the bytes this pays.
@ sha256_snapshot Sha256 h__h → ( Vec u ) {
    : *Sha256Impl h ( __Sha256_ptr h__h )
    : *u32 sp ( vec_data [u32] . h w )
    : *u32 snap # *u32 + # i sp 32
    ( nurl_memcpy # s snap # s sp 32 )
    : *u sblk # *u + # i sp 448
    ( nurl_memcpy # s sblk # s + # i sp 320 . h blen )
    ^ ( __sha256_finish snap sblk . h blen . h total . h k # *u32 + # i sp 64 )
}

// One-shot over the streaming core.
@ sha256_pure ( Vec u ) data → ( Vec u ) {
    : Sha256 h ( sha256_init )
    ( sha256_update h data )
    ^ ( sha256_final h )
}

// ── HMAC-SHA-256 (RFC 2104; block size B = 64 bytes for SHA-256). ──
//
// Both legs stream through one hasher: the padded key block goes in,
// then the message (or the inner digest) straight from the caller's
// buffer — no `ipad ‖ msg` concatenation is built. A TLS key schedule
// runs this a few dozen times per handshake.

// Start `h` over as a fresh SHA-256 stream (its block is reused).
@ __sha256_restart Sha256 h__h → v {
    : *Sha256Impl h ( __Sha256_ptr h__h )
    : *u32 sp ( vec_data [u32] . h w )
    = . sp 0 # u32 1779033703
    = . sp 1 # u32 3144134277
    = . sp 2 # u32 1013904242
    = . sp 3 # u32 2773480762
    = . sp 4 # u32 1359893119
    = . sp 5 # u32 2600822924
    = . sp 6 # u32 528734635
    = . sp 7 # u32 1541459225
    = . h blen 0
    = . h total 0
}

@ hmac_sha256_pure ( Vec u ) key ( Vec u ) msg → ( Vec u ) {
    // K0: the key, hashed down first when longer than a block, then
    // zero-padded to 64 bytes.
    : ( Vec u ) pad ( vec_with_cap [u] 64 )
    : b _l ( vec_set_len [u] pad 64 )
    : *u pp ( vec_data [u] pad )
    ( nurl_memset # s pp 0 64 )
    : i klen ( vec_len [u] key )
    ? > klen 64 {
        : ( Vec u ) khash ( sha256_pure key )
        ( nurl_memcpy # s pp # s ( vec_data [u] khash ) 32 )
    } {
        ? > klen 0 { ( nurl_memcpy # s pp # s ( vec_data [u] key ) klen ) } {}
    }

    // inner = SHA-256((K0 ^ ipad) ‖ msg)
    : ~ i xi 0
    ~ < xi 64 {
        = . pp xi # u ^^ # i . pp xi 54
        = xi + xi 1
    }
    : Sha256 h ( sha256_init )
    ( sha256_update h pad )
    ( sha256_update h msg )
    : ( Vec u ) inner ( sha256_final h )

    // outer = SHA-256((K0 ^ opad) ‖ inner); ipad ^ opad = 0x36 ^ 0x5c = 0x6a
    = xi 0
    ~ < xi 64 {
        = . pp xi # u ^^ # i . pp xi 106
        = xi + xi 1
    }
    ( __sha256_restart h )
    ( sha256_update h pad )
    ( sha256_update h inner )
    ^ ( sha256_final h )
}

// ── SHA-224 (FIPS 180-4 §6.2) ──────────────────────────────────────
//
// The SHA-256 compression function with a different initial state,
// truncated to 224 bits. Nothing else changes — same block size, same
// round constants, same schedule — which is why this reuses the whole
// machinery above rather than repeating it.
//
// It exists here for HashML-DSA: FIPS 204's pre-hash mode names twelve
// approved digests by OID, and a caller who picks SHA2-224 needs the
// signer to compute exactly that.
@ sha224_pure ( Vec u ) data → ( Vec u ) {
    : Sha256 h ( sha256_init )
    : *u32 sp ( vec_data [u32] . ( __Sha256_ptr h ) w )
    = . sp 0 # u32 3238371032
    = . sp 1 # u32 914150663
    = . sp 2 # u32 812702999
    = . sp 3 # u32 4144912697
    = . sp 4 # u32 4290775857
    = . sp 5 # u32 1750603025
    = . sp 6 # u32 1694076839
    = . sp 7 # u32 3204075428
    ( sha256_update h data )
    : ( Vec u ) full ( sha256_final h )
    ^ ( bytes_slice full 0 28 )
}
