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
@ __sha256_rotr u32 x i c → u32 {
    : u32 cu # u32 c
    : u32 inv # u32 - 32 c
    ^ | >> x cu << x inv
}

// ── 64-entry round-constant table per FIPS 180-4 §4.2.2 ────────────

@ __sha256_K → ( Vec u32 ) {
    : ( Vec u32 ) k ( vec_with_cap [u32] 64 )
    ( vec_push [u32] k # u32 1116352408 )
    ( vec_push [u32] k # u32 1899447441 )
    ( vec_push [u32] k # u32 3049323471 )
    ( vec_push [u32] k # u32 3921009573 )
    ( vec_push [u32] k # u32 961987163 )
    ( vec_push [u32] k # u32 1508970993 )
    ( vec_push [u32] k # u32 2453635748 )
    ( vec_push [u32] k # u32 2870763221 )
    ( vec_push [u32] k # u32 3624381080 )
    ( vec_push [u32] k # u32 310598401 )
    ( vec_push [u32] k # u32 607225278 )
    ( vec_push [u32] k # u32 1426881987 )
    ( vec_push [u32] k # u32 1925078388 )
    ( vec_push [u32] k # u32 2162078206 )
    ( vec_push [u32] k # u32 2614888103 )
    ( vec_push [u32] k # u32 3248222580 )
    ( vec_push [u32] k # u32 3835390401 )
    ( vec_push [u32] k # u32 4022224774 )
    ( vec_push [u32] k # u32 264347078 )
    ( vec_push [u32] k # u32 604807628 )
    ( vec_push [u32] k # u32 770255983 )
    ( vec_push [u32] k # u32 1249150122 )
    ( vec_push [u32] k # u32 1555081692 )
    ( vec_push [u32] k # u32 1996064986 )
    ( vec_push [u32] k # u32 2554220882 )
    ( vec_push [u32] k # u32 2821834349 )
    ( vec_push [u32] k # u32 2952996808 )
    ( vec_push [u32] k # u32 3210313671 )
    ( vec_push [u32] k # u32 3336571891 )
    ( vec_push [u32] k # u32 3584528711 )
    ( vec_push [u32] k # u32 113926993 )
    ( vec_push [u32] k # u32 338241895 )
    ( vec_push [u32] k # u32 666307205 )
    ( vec_push [u32] k # u32 773529912 )
    ( vec_push [u32] k # u32 1294757372 )
    ( vec_push [u32] k # u32 1396182291 )
    ( vec_push [u32] k # u32 1695183700 )
    ( vec_push [u32] k # u32 1986661051 )
    ( vec_push [u32] k # u32 2177026350 )
    ( vec_push [u32] k # u32 2456956037 )
    ( vec_push [u32] k # u32 2730485921 )
    ( vec_push [u32] k # u32 2820302411 )
    ( vec_push [u32] k # u32 3259730800 )
    ( vec_push [u32] k # u32 3345764771 )
    ( vec_push [u32] k # u32 3516065817 )
    ( vec_push [u32] k # u32 3600352804 )
    ( vec_push [u32] k # u32 4094571909 )
    ( vec_push [u32] k # u32 275423344 )
    ( vec_push [u32] k # u32 430227734 )
    ( vec_push [u32] k # u32 506948616 )
    ( vec_push [u32] k # u32 659060556 )
    ( vec_push [u32] k # u32 883997877 )
    ( vec_push [u32] k # u32 958139571 )
    ( vec_push [u32] k # u32 1322822218 )
    ( vec_push [u32] k # u32 1537002063 )
    ( vec_push [u32] k # u32 1747873779 )
    ( vec_push [u32] k # u32 1955562222 )
    ( vec_push [u32] k # u32 2024104815 )
    ( vec_push [u32] k # u32 2227730452 )
    ( vec_push [u32] k # u32 2361852424 )
    ( vec_push [u32] k # u32 2428436474 )
    ( vec_push [u32] k # u32 2756734187 )
    ( vec_push [u32] k # u32 3204031479 )
    ( vec_push [u32] k # u32 3329325298 )
    ^ k
}

// ── Transform one 64-byte block. Mutates state (8 × u32) in place.

@ __sha256_transform ( Vec u32 ) state ( Vec u ) block i offset ( Vec u32 ) K → v {
    : ( Vec u32 ) m ( vec_with_cap [u32] 64 )
    : ~ i wi 0
    ~ < wi 16 {
        : ?u32 wo ( bytes_read_u32_be block + offset * wi 4 )
        : u32 wv ?? wo { T x → x F → # u32 0 }
        ( vec_push [u32] m wv )
        = wi + wi 1
    }
    ~ < wi 64 {
        : u32 m15 ( __sha256_vu32 m - wi 15 )
        : u32 m2 ( __sha256_vu32 m - wi 2 )
        : u32 m7 ( __sha256_vu32 m - wi 7 )
        : u32 m16 ( __sha256_vu32 m - wi 16 )
        : u32 s0 ^^ ^^ ( __sha256_rotr m15 7 ) ( __sha256_rotr m15 18 ) >> m15 # u32 3
        : u32 s1 ^^ ^^ ( __sha256_rotr m2 17 ) ( __sha256_rotr m2 19 ) >> m2 # u32 10
        ( vec_push [u32] m + + + m16 s0 m7 s1 )
        = wi + wi 1
    }

    : ~ u32 a ( __sha256_vu32 state 0 )
    : ~ u32 b ( __sha256_vu32 state 1 )
    : ~ u32 c ( __sha256_vu32 state 2 )
    : ~ u32 d ( __sha256_vu32 state 3 )
    : ~ u32 e ( __sha256_vu32 state 4 )
    : ~ u32 f ( __sha256_vu32 state 5 )
    : ~ u32 g ( __sha256_vu32 state 6 )
    : ~ u32 h ( __sha256_vu32 state 7 )

    : ~ i ri 0
    ~ < ri 64 {
        : u32 S1 ^^ ^^ ( __sha256_rotr e 6 ) ( __sha256_rotr e 11 ) ( __sha256_rotr e 25 )
        : u32 ch ^^ & e f & ~ e g
        : u32 ki ( __sha256_vu32 K ri )
        : u32 mi ( __sha256_vu32 m ri )
        : u32 t1 + + + + h S1 ch ki mi
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

    : u32 s0 ( __sha256_vu32 state 0 )
    : u32 s1 ( __sha256_vu32 state 1 )
    : u32 s2 ( __sha256_vu32 state 2 )
    : u32 s3 ( __sha256_vu32 state 3 )
    : u32 s4 ( __sha256_vu32 state 4 )
    : u32 s5 ( __sha256_vu32 state 5 )
    : u32 s6 ( __sha256_vu32 state 6 )
    : u32 s7 ( __sha256_vu32 state 7 )
    : b _0 ( vec_set [u32] state 0 + s0 a )
    : b _1 ( vec_set [u32] state 1 + s1 b )
    : b _2 ( vec_set [u32] state 2 + s2 c )
    : b _3 ( vec_set [u32] state 3 + s3 d )
    : b _4 ( vec_set [u32] state 4 + s4 e )
    : b _5 ( vec_set [u32] state 5 + s5 f )
    : b _6 ( vec_set [u32] state 6 + s6 g )
    : b _7 ( vec_set [u32] state 7 + s7 h )

    ( vec_free [u32] m )
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
    = . h k ( __sha256_K )
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
            ( __sha256_transform . h state . h buf 0 . h k )
            ( vec_clear [u] . h buf )
        } {}
    } {}
    // full blocks straight from the caller's data — no copy
    ~ <= + off 64 n {
        ( __sha256_transform . h state data off . h k )
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
        ( __sha256_transform . h state tail toff . h k )
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
    ( vec_free [u32] . h k )
    ( nurl_free # s h )
    ^ out
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
