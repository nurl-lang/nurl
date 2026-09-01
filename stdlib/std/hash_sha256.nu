// stdlib/std/hash_sha256.nu — FIPS 180-4 SHA-256 in pure NURL.
//
// API:
//   ( sha256_pure ( Vec u ) data )       → ( Vec u )   32-byte digest
//   ( hmac_sha256_pure ( Vec u ) key
//                       ( Vec u ) msg )   → ( Vec u )   32-byte HMAC

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ __sha256_vu32 ( Vec u32 ) v i idx → u32 {
    : ?u32 o ( vec_get [u32] v idx )
    ?? o { T x → { ^ x } F → { ^ # u32 0 } }
}

@ __sha256_vu8 ( Vec u ) v i idx → i {
    : ?u o ( vec_get [u] v idx )
    ?? o { T x → { ^ # i x } F → { ^ 0 } }
}

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
// a heap alloc/free per digest bought nothing. Benign init race: two
// first callers may both build; one pointer wins, the losing 256-byte
// copy leaks once (same discipline as the P-256 comb tables).
: ~ i g_sha256_k 0

@ __sha256_k_shared → ( Vec u32 ) {
    ? == g_sha256_k 0 {
        : ( Vec u32 ) k ( __sha256_K )
        = g_sha256_k # i . k ctl
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
// Every limb here goes through a raw `*u32` / `*u` rather than the
// bounds-checked Vec accessors. One block used to make about 380 of those
// calls — 64 pushes to build the message schedule, 192 gets to expand it,
// and 128 more to read K and the schedule back in the round loop — for a
// compression function whose actual work is 64 rounds of ALU. The indices
// are all fixed-count and provably in range, so the checks were pure
// overhead; they showed up as 12% of a TLS handshake.
//
// The schedule `m` is the caller's 64-word scratch, allocated once per
// hash instead of once per block.

@ __sha256_be32 * u p i o → u32 {
    ^ | | | << # u32 . p o # u32 24 << # u32 . p + o 1 # u32 16
    << # u32 . p + o 2 # u32 8 # u32 . p + o 3
}

@ __sha256_transform ( Vec u32 ) state ( Vec u ) block i offset ( Vec u32 ) K ( Vec u32 ) m → v {
    : *u32 mp ( vec_data [u32] m )
    : *u32 kp ( vec_data [u32] K )
    : *u32 sp ( vec_data [u32] state )
    : *u bp ( vec_data [u] block )
    : ~ i wi 0
    ~ < wi 16 {
        = . mp wi ( __sha256_be32 bp + offset * wi 4 )
        = wi + wi 1
    }
    ~ < wi 64 {
        : u32 m15 . mp - wi 15
        : u32 m2 . mp - wi 2
        : u32 s0 ^^ ^^ ( __sha256_rotr m15 7 ) ( __sha256_rotr m15 18 ) >> m15 # u32 3
        : u32 s1 ^^ ^^ ( __sha256_rotr m2 17 ) ( __sha256_rotr m2 19 ) >> m2 # u32 10
        = . mp wi + + + . mp - wi 16 s0 . mp - wi 7 s1
        = wi + wi 1
    }

    : ~ u32 a . sp 0
    : ~ u32 b . sp 1
    : ~ u32 c . sp 2
    : ~ u32 d . sp 3
    : ~ u32 e . sp 4
    : ~ u32 f . sp 5
    : ~ u32 g . sp 6
    : ~ u32 h . sp 7

    : ~ i ri 0
    ~ < ri 64 {
        : u32 S1 ^^ ^^ ( __sha256_rotr e 6 ) ( __sha256_rotr e 11 ) ( __sha256_rotr e 25 )
        : u32 ch ^^ & e f & ~ e g
        : u32 t1 + + + + h S1 ch . kp ri . mp ri
        : u32 S0 ^^ ^^ ( __sha256_rotr a 2 ) ( __sha256_rotr a 13 ) ( __sha256_rotr a 22 )
        : u32 mj ^^ ^^ & a b & a c & b c
        : u32 t2 + S0 mj
        = h g
        = g f
        = f e
        = e + d t1
        = d c
        = c b
        = b a
        = a + t1 t2
        = ri + ri 1
    }

    = . sp 0 + . sp 0 a
    = . sp 1 + . sp 1 b
    = . sp 2 + . sp 2 c
    = . sp 3 + . sp 3 d
    = . sp 4 + . sp 4 e
    = . sp 5 + . sp 5 f
    = . sp 6 + . sp 6 g
    = . sp 7 + . sp 7 h
}

// ── Public entry — bytes-in, 32-byte digest out.

// ── Incremental (streaming) hashing ────────────────────────────────
//
// Hash gigabytes without holding them: feed pieces as they arrive
// (file_read_chunk, an HTTP stream) and finalize once. The one-shot
// sha256_pure below is a thin init/update/final composition, so the
// two paths cannot drift.
//
//   ( sha256_init )          → *Sha256
//   ( sha256_update h v )    → v          any piece size, any count
//   ( sha256_final h )       → ( Vec u )  32-byte digest; FREES h —
//                                          the handle is dead after this

: Sha256 {
    ( Vec u32 ) state
    ( Vec u ) buf
    i total
    ( Vec u32 ) k
    ( Vec u32 ) m
}

@ sha256_init → *Sha256 {
    : *Sha256 h # *Sha256 ( nurl_alloc Z Sha256 )
    : ( Vec u32 ) st ( vec_with_cap [u32] 8 )
    ( vec_push [u32] st # u32 1779033703 )
    ( vec_push [u32] st # u32 3144134277 )
    ( vec_push [u32] st # u32 1013904242 )
    ( vec_push [u32] st # u32 2773480762 )
    ( vec_push [u32] st # u32 1359893119 )
    ( vec_push [u32] st # u32 2600822924 )
    ( vec_push [u32] st # u32 528734635 )
    ( vec_push [u32] st # u32 1541459225 )
    = . h state st
    = . h buf ( vec_new [u] )
    = . h total 0
    = . h k ( __sha256_k_shared )
    : ( Vec u32 ) sched ( vec_with_cap [u32] 64 )
    : b _m ( vec_set_len [u32] sched 64 )
    = . h m sched
    ^ h
}

@ sha256_update * Sha256 h ( Vec u ) data → v {
    : i n ( vec_len [u] data )
    ? <= n 0 { ^ v } {}
    = . h total + . h total n
    : ~ i off 0
    // top up a partial block first
    : i have ( vec_len [u] . h buf )
    ? > have 0 {
        : i need - 64 have
        : i take ? < n need n need
        ( bytes_extend_raw . h buf # s ( vec_data [u] data ) take )
        = off take
        ? == ( vec_len [u] . h buf ) 64 {
            ( __sha256_transform . h state . h buf 0 . h k . h m )
            ( vec_clear [u] . h buf )
        } {}
    } {}
    // full blocks straight from the caller's data — no copy
    ~ <= + off 64 n {
        ( __sha256_transform . h state data off . h k . h m )
        = off + off 64
    }
    // stash the tail
    ? < off n {
        ( bytes_extend_raw . h buf # s + # i ( vec_data [u] data ) off - n off )
    } {}
}

// Digest and DESTROY: pads, runs the final block(s), serialises the
// state big-endian, and frees every part of the handle.
@ sha256_final * Sha256 h → ( Vec u ) {
    : ( Vec u ) tail . h buf
    ( vec_push [u] tail # u 128 )
    : i leftover % . h total 64
    : i after_one + leftover 1
    : i need_zeros ? <= after_one 56 - 56 after_one - 120 after_one
    : ~ i zi 0
    ~ < zi need_zeros {
        ( vec_push [u] tail # u 0 )
        = zi + zi 1
    }
    : i bitlen * . h total 8
    ( vec_push [u] tail # u & >> bitlen 56 255 )
    ( vec_push [u] tail # u & >> bitlen 48 255 )
    ( vec_push [u] tail # u & >> bitlen 40 255 )
    ( vec_push [u] tail # u & >> bitlen 32 255 )
    ( vec_push [u] tail # u & >> bitlen 24 255 )
    ( vec_push [u] tail # u & >> bitlen 16 255 )
    ( vec_push [u] tail # u & >> bitlen 8 255 )
    ( vec_push [u] tail # u & bitlen 255 )
    : i tail_len ( vec_len [u] tail )
    : ~ i toff 0
    ~ < toff tail_len {
        ( __sha256_transform . h state tail toff . h k . h m )
        = toff + toff 64
    }

    : ( Vec u ) out ( vec_with_cap [u] 32 )
    : ~ i si 0
    ~ < si 8 {
        : u32 sv ( __sha256_vu32 . h state si )
        : i siv # i sv
        ( vec_push [u] out # u & >> siv 24 255 )
        ( vec_push [u] out # u & >> siv 16 255 )
        ( vec_push [u] out # u & >> siv 8 255 )
        ( vec_push [u] out # u & siv 255 )
        = si + si 1
    }
    ( vec_free [u] tail )
    ( vec_free [u32] . h state )
    // h.k is the shared process-global constant table — never freed.
    ( vec_free [u32] . h m )
    ( nurl_free # s h )
    ^ out
}

// Digest-so-far WITHOUT consuming the stream: clones the running state
// and finalises the clone; `h` stays live and can keep absorbing. This
// is what an incremental transcript hash needs — TLS 1.3 reads the
// transcript digest at five points while the transcript keeps growing,
// and re-hashing the whole transcript from scratch at each point costs
// ~5× the bytes this pays.
@ sha256_snapshot * Sha256 h → ( Vec u ) {
    : *Sha256 c # *Sha256 ( nurl_alloc Z Sha256 )
    = . c state ( vec_clone [u32] . h state )
    = . c buf ( vec_clone [u] . h buf )
    = . c total . h total
    = . c k . h k
    = . c m ( vec_clone [u32] . h m )
    ^ ( sha256_final c )
}

// One-shot over the streaming core.
@ sha256_pure ( Vec u ) data → ( Vec u ) {
    : *Sha256 h ( sha256_init )
    ( sha256_update h data )
    ^ ( sha256_final h )
}

// ── HMAC-SHA-256 (RFC 2104; block size B = 64 bytes for SHA-256). ──

@ hmac_sha256_pure ( Vec u ) key ( Vec u ) msg → ( Vec u ) {
    : i klen ( vec_len [u] key )
    : ( Vec u ) kbuf ( vec_with_cap [u] 64 )

    // Reduce key to <= 64 bytes by hashing if needed; right-pad with 0.
    ? > klen 64 {
        : ( Vec u ) khash ( sha256_pure key )
        : ~ i ki 0
        ~ < ki 32 {
            ( vec_push [u] kbuf # u & ( __sha256_vu8 khash ki ) 255 )
            = ki + ki 1
        }
        ( vec_free [u] khash )
    } {
        : ~ i ki 0
        ~ < ki klen {
            ( vec_push [u] kbuf # u & ( __sha256_vu8 key ki ) 255 )
            = ki + ki 1
        }
    }
    : ~ i pi ( vec_len [u] kbuf )
    ~ < pi 64 {
        ( vec_push [u] kbuf # u 0 )
        = pi + pi 1
    }

    // Build inner/outer pads.
    : ( Vec u ) ipad ( vec_with_cap [u] 64 )
    : ( Vec u ) opad ( vec_with_cap [u] 64 )
    : ~ i xi 0
    ~ < xi 64 {
        : i kb ( __sha256_vu8 kbuf xi )
        ( vec_push [u] ipad # u & ^^ kb 54 255 )
        ( vec_push [u] opad # u & ^^ kb 92 255 )
        = xi + xi 1
    }

    // inner = SHA-256(ipad || msg)
    : i mlen ( vec_len [u] msg )
    : ( Vec u ) inner_input ( vec_with_cap [u] + 64 mlen )
    : ~ i ii 0
    ~ < ii 64 {
        ( vec_push [u] inner_input # u & ( __sha256_vu8 ipad ii ) 255 )
        = ii + ii 1
    }
    : ~ i mi 0
    ~ < mi mlen {
        ( vec_push [u] inner_input # u & ( __sha256_vu8 msg mi ) 255 )
        = mi + mi 1
    }
    : ( Vec u ) inner ( sha256_pure inner_input )
    ( vec_free [u] inner_input )

    // outer = SHA-256(opad || inner)
    : ( Vec u ) outer_input ( vec_with_cap [u] 96 )
    : ~ i oi 0
    ~ < oi 64 {
        ( vec_push [u] outer_input # u & ( __sha256_vu8 opad oi ) 255 )
        = oi + oi 1
    }
    : ~ i ni 0
    ~ < ni 32 {
        ( vec_push [u] outer_input # u & ( __sha256_vu8 inner ni ) 255 )
        = ni + ni 1
    }
    : ( Vec u ) mac ( sha256_pure outer_input )
    ( vec_free [u] outer_input )
    ( vec_free [u] inner )
    ( vec_free [u] ipad )
    ( vec_free [u] opad )
    ( vec_free [u] kbuf )
    ^ mac
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
    : *Sha256 h ( sha256_init )
    : *u32 sp ( vec_data [u32] . h state )
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
    : ( Vec u ) out ( bytes_slice full 0 28 )
    ( vec_free [u] full )
    ^ out
}
