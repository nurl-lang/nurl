// stdlib/std/hash_sha512.nu — FIPS 180-4 SHA-512 + HMAC in pure NURL.
//
// 64-bit word SHA-2 with 128-byte blocks and 80 rounds.
//
// API:
//   ( sha512_pure ( Vec u ) data )       → ( Vec u )   64-byte digest
//   ( hmac_sha512_pure ( Vec u ) key
//                       ( Vec u ) msg )   → ( Vec u )   64-byte HMAC
//
// u64 constants > 2^63-1 are written as their negative-two's-
// complement i64 equivalents (NURL has no hex literals; decimal-
// literal lexer caps at LLONG_MAX). `# u64 -N` is a zero-cost
// reinterpretation of the i64 bit pattern as u64.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ __sha512_vu64 ( Vec u64 ) v i idx → u64 {
    : ?u64 o ( vec_get [u64] v idx )
    ?? o { T x → { ^ x } F → { ^ # u64 0 } }
}

@ __sha512_vu8 ( Vec u ) v i idx → i {
    : ?u o ( vec_get [u] v idx )
    ?? o { T x → { ^ # i x } F → { ^ 0 } }
}

// Right-rotate u64 by c bits (0 < c < 64).
@ __sha512_rotr u64 x i c → u64 {
    // One `ror` instruction via the compiler's funnel-shift primitive,
    // rather than a shift pair, an `or` and the two intermediate
    // values they need materialised — see __sha256_rotr for the full
    // note. Every ISA NURL targets has the instruction.
    ^ # u64 ( nurl_rotr64 # u64 x # u64 c )
}

// ── 80-entry K table (FIPS 180-4 §4.2.3) ──────────────────────────

@ __sha512_K → ( Vec u64 ) {
    // Filled by index through a raw `*u64` — see hash_sha256.nu's K for why
    // eighty capacity-checked pushes per hash are eighty too many.
    : ( Vec u64 ) k ( vec_with_cap [u64] 80 )
    : b _l ( vec_set_len [u64] k 80 )
    : *u64 kp ( vec_data [u64] k )
    = . kp 0 # u64 4794697086780616226 = . kp 1 # u64 8158064640168781261
    = . kp 2 # u64 -5349999486874862801 = . kp 3 # u64 -1606136188198331460
    = . kp 4 # u64 4131703408338449720 = . kp 5 # u64 6480981068601479193
    = . kp 6 # u64 -7908458776815382629 = . kp 7 # u64 -6116909921290321640
    = . kp 8 # u64 -2880145864133508542 = . kp 9 # u64 1334009975649890238
    = . kp 10 # u64 2608012711638119052 = . kp 11 # u64 6128411473006802146
    = . kp 12 # u64 8268148722764581231 = . kp 13 # u64 -9160688886553864527
    = . kp 14 # u64 -7215885187991268811 = . kp 15 # u64 -4495734319001033068
    = . kp 16 # u64 -1973867731355612462 = . kp 17 # u64 -1171420211273849373
    = . kp 18 # u64 1135362057144423861 = . kp 19 # u64 2597628984639134821
    = . kp 20 # u64 3308224258029322869 = . kp 21 # u64 5365058923640841347
    = . kp 22 # u64 6679025012923562964 = . kp 23 # u64 8573033837759648693
    = . kp 24 # u64 -7476448914759557205 = . kp 25 # u64 -6327057829258317296
    = . kp 26 # u64 -5763719355590565569 = . kp 27 # u64 -4658551843659510044
    = . kp 28 # u64 -4116276920077217854 = . kp 29 # u64 -3051310485924567259
    = . kp 30 # u64 489312712824947311 = . kp 31 # u64 1452737877330783856
    = . kp 32 # u64 2861767655752347644 = . kp 33 # u64 3322285676063803686
    = . kp 34 # u64 5560940570517711597 = . kp 35 # u64 5996557281743188959
    = . kp 36 # u64 7280758554555802590 = . kp 37 # u64 8532644243296465576
    = . kp 38 # u64 -9096487096722542874 = . kp 39 # u64 -7894198246740708037
    = . kp 40 # u64 -6719396339535248540 = . kp 41 # u64 -6333637450476146687
    = . kp 42 # u64 -4446306890439682159 = . kp 43 # u64 -4076793802049405392
    = . kp 44 # u64 -3345356375505022440 = . kp 45 # u64 -2983346525034927856
    = . kp 46 # u64 -860691631967231958 = . kp 47 # u64 1182934255886127544
    = . kp 48 # u64 1847814050463011016 = . kp 49 # u64 2177327727835720531
    = . kp 50 # u64 2830643537854262169 = . kp 51 # u64 3796741975233480872
    = . kp 52 # u64 4115178125766777443 = . kp 53 # u64 5681478168544905931
    = . kp 54 # u64 6601373596472566643 = . kp 55 # u64 7507060721942968483
    = . kp 56 # u64 8399075790359081724 = . kp 57 # u64 8693463985226723168
    = . kp 58 # u64 -8878714635349349518 = . kp 59 # u64 -8302665154208450068
    = . kp 60 # u64 -8016688836872298968 = . kp 61 # u64 -6606660893046293015
    = . kp 62 # u64 -4685533653050689259 = . kp 63 # u64 -4147400797238176981
    = . kp 64 # u64 -3880063495543823972 = . kp 65 # u64 -3348786107499101689
    = . kp 66 # u64 -1523767162380948706 = . kp 67 # u64 -757361751448694408
    = . kp 68 # u64 500013540394364858 = . kp 69 # u64 748580250866718886
    = . kp 70 # u64 1242879168328830382 = . kp 71 # u64 1977374033974150939
    = . kp 72 # u64 2944078676154940804 = . kp 73 # u64 3659926193048069267
    = . kp 74 # u64 4368137639120453308 = . kp 75 # u64 4836135668995329356
    = . kp 76 # u64 5532061633213252278 = . kp 77 # u64 6448918945643986474
    = . kp 78 # u64 6902733635092675308 = . kp 79 # u64 7801388544844847127
    ^ k
}

// ── Transform: one 128-byte block. Mutates state (8 × u64) in place.
//
// Limbs go through raw `*u64` / `*u` rather than the bounds-checked Vec
// accessors, and the 80-word message schedule `w` is the caller's scratch
// — allocated once per hash instead of once per block. Same change, same
// reasoning as hash_sha256.nu.

@ __sha512_be64 * u p i o → u64 {
    ^ | | | | | | | << # u64 . p o # u64 56 << # u64 . p + o 1 # u64 48
    << # u64 . p + o 2 # u64 40 << # u64 . p + o 3 # u64 32
    << # u64 . p + o 4 # u64 24 << # u64 . p + o 5 # u64 16
    << # u64 . p + o 6 # u64 8 # u64 . p + o 7
}

@ __sha512_transform ( Vec u64 ) state ( Vec u ) block i offset ( Vec u64 ) K ( Vec u64 ) w → v {
    : *u64 wp ( vec_data [u64] w )
    : *u64 kp ( vec_data [u64] K )
    : *u64 sp ( vec_data [u64] state )
    : *u bp ( vec_data [u] block )
    : ~ i wi 0
    ~ < wi 16 {
        = . wp wi ( __sha512_be64 bp + offset * wi 8 )
        = wi + wi 1
    }
    ~ < wi 80 {
        : u64 w15 . wp - wi 15
        : u64 w2 . wp - wi 2
        : u64 s0 ^^ ^^ ( __sha512_rotr w15 1 ) ( __sha512_rotr w15 8 ) >> w15 # u64 7
        : u64 s1 ^^ ^^ ( __sha512_rotr w2 19 ) ( __sha512_rotr w2 61 ) >> w2 # u64 6
        = . wp wi + + + . wp - wi 16 s0 . wp - wi 7 s1
        = wi + wi 1
    }

    : ~ u64 a . sp 0
    : ~ u64 b . sp 1
    : ~ u64 c . sp 2
    : ~ u64 d . sp 3
    : ~ u64 e . sp 4
    : ~ u64 f . sp 5
    : ~ u64 g . sp 6
    : ~ u64 h . sp 7

    : ~ i ri 0
    ~ < ri 80 {
        : u64 S1 ^^ ^^ ( __sha512_rotr e 14 ) ( __sha512_rotr e 18 ) ( __sha512_rotr e 41 )
        : u64 ch ^^ & e f & ~ e g
        : u64 t1 + + + + h S1 ch . kp ri . wp ri
        : u64 S0 ^^ ^^ ( __sha512_rotr a 28 ) ( __sha512_rotr a 34 ) ( __sha512_rotr a 39 )
        : u64 mj ^^ ^^ & a b & a c & b c
        : u64 t2 + S0 mj
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

// ── Public entry — bytes-in, 64-byte digest out. ──────────────────

@ sha512_pure ( Vec u ) data → ( Vec u ) {
    : ( Vec u64 ) state ( vec_with_cap [u64] 8 )
    ( vec_push [u64] state # u64 7640891576956012808 )
    ( vec_push [u64] state # u64 -4942790177534073029 )
    ( vec_push [u64] state # u64 4354685564936845355 )
    ( vec_push [u64] state # u64 -6534734903238641935 )
    ( vec_push [u64] state # u64 5840696475078001361 )
    ( vec_push [u64] state # u64 -7276294671716946913 )
    ( vec_push [u64] state # u64 2270897969802886507 )
    ( vec_push [u64] state # u64 6620516959819538809 )
    ^ ( __sha512_finish data state 64 )
}

// SHA-384 — SHA-512 with a distinct IV, truncated to 48 bytes.
@ sha384_pure ( Vec u ) data → ( Vec u ) {
    : ( Vec u64 ) state ( vec_with_cap [u64] 8 )
    ( vec_push [u64] state # u64 -3766243637369397544 )
    ( vec_push [u64] state # u64 7105036623409894663 )
    ( vec_push [u64] state # u64 -7973340178411365097 )
    ( vec_push [u64] state # u64 1526699215303891257 )
    ( vec_push [u64] state # u64 7436329637833083697 )
    ( vec_push [u64] state # u64 -8163818279084223215 )
    ( vec_push [u64] state # u64 -2662702644619276377 )
    ( vec_push [u64] state # u64 5167115440072839076 )
    ^ ( __sha512_finish data state 48 )
}

// Shared SHA-512/384 finaliser: pad, transform, and serialise the state
// to `outlen` bytes. Consumes `state`.
@ __sha512_finish ( Vec u ) data ( Vec u64 ) state i outlen → ( Vec u ) {
    : ( Vec u64 ) K ( __sha512_K )
    : ( Vec u64 ) sched ( vec_with_cap [u64] 80 )
    : b _w ( vec_set_len [u64] sched 80 )
    : i n ( vec_len [u] data )

    // Process complete 128-byte blocks straight from the input.
    : ~ i off 0
    ~ <= + off 128 n {
        ( __sha512_transform state data off K sched )
        = off + off 128
    }

    // Tail: leftover bytes + 0x80 + zero pad + 128-bit BIG-endian
    // length (high 64 bits always zero — max input 2^61 bytes
    // matches the same i64-bit-counter bound the C version held).
    : ( Vec u ) tail ( vec_with_cap [u] 256 )
    : ~ i ti off
    ~ < ti n {
        : i bv ( __sha512_vu8 data ti )
        ( vec_push [u] tail # u & bv 255 )
        = ti + ti 1
    }
    ( vec_push [u] tail # u 128 )
    : i leftover - n off
    : i after_one + leftover 1
    : i need_zeros ? <= after_one 112 - 112 after_one - 240 after_one
    : ~ i zi 0
    ~ < zi need_zeros {
        ( vec_push [u] tail # u 0 )
        = zi + zi 1
    }
    : i bitlen * n 8
    // Upper 64 bits of the 128-bit length are always zero.
    : ~ i zh 0
    ~ < zh 8 {
        ( vec_push [u] tail # u 0 )
        = zh + zh 1
    }
    // Lower 64 bits — big-endian.
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
        ( __sha512_transform state tail toff K sched )
        = toff + toff 128
    }
    ( vec_free [u] tail )

    // Serialise state[0..8] as 64 big-endian bytes.
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    : ~ i si 0
    ~ < si 8 {
        : u64 sv ( __sha512_vu64 state si )
        : i siv # i sv
        ( vec_push [u] out # u & >> siv 56 255 )
        ( vec_push [u] out # u & >> siv 48 255 )
        ( vec_push [u] out # u & >> siv 40 255 )
        ( vec_push [u] out # u & >> siv 32 255 )
        ( vec_push [u] out # u & >> siv 24 255 )
        ( vec_push [u] out # u & >> siv 16 255 )
        ( vec_push [u] out # u & >> siv 8 255 )
        ( vec_push [u] out # u & siv 255 )
        = si + si 1
    }

    ( vec_free [u64] state )
    ( vec_free [u64] K )
    ( vec_free [u64] sched )
    : b _t ( vec_set_len [u] out outlen )
    ^ out
}

// ── HMAC-SHA-512 (RFC 2104; block size B = 128 bytes). ────────────

@ hmac_sha512_pure ( Vec u ) key ( Vec u ) msg → ( Vec u ) {
    : i klen ( vec_len [u] key )
    : ( Vec u ) kbuf ( vec_with_cap [u] 128 )

    ? > klen 128 {
        : ( Vec u ) khash ( sha512_pure key )
        : ~ i ki 0
        ~ < ki 64 {
            ( vec_push [u] kbuf # u & ( __sha512_vu8 khash ki ) 255 )
            = ki + ki 1
        }
        ( vec_free [u] khash )
    } {
        : ~ i ki 0
        ~ < ki klen {
            ( vec_push [u] kbuf # u & ( __sha512_vu8 key ki ) 255 )
            = ki + ki 1
        }
    }
    : ~ i pi ( vec_len [u] kbuf )
    ~ < pi 128 {
        ( vec_push [u] kbuf # u 0 )
        = pi + pi 1
    }

    : ( Vec u ) ipad ( vec_with_cap [u] 128 )
    : ( Vec u ) opad ( vec_with_cap [u] 128 )
    : ~ i xi 0
    ~ < xi 128 {
        : i kb ( __sha512_vu8 kbuf xi )
        ( vec_push [u] ipad # u & ^^ kb 54 255 )
        ( vec_push [u] opad # u & ^^ kb 92 255 )
        = xi + xi 1
    }

    : i mlen ( vec_len [u] msg )
    : ( Vec u ) inner_input ( vec_with_cap [u] + 128 mlen )
    : ~ i ii 0
    ~ < ii 128 {
        ( vec_push [u] inner_input # u & ( __sha512_vu8 ipad ii ) 255 )
        = ii + ii 1
    }
    : ~ i mi 0
    ~ < mi mlen {
        ( vec_push [u] inner_input # u & ( __sha512_vu8 msg mi ) 255 )
        = mi + mi 1
    }
    : ( Vec u ) inner ( sha512_pure inner_input )
    ( vec_free [u] inner_input )

    : ( Vec u ) outer_input ( vec_with_cap [u] 192 )
    : ~ i oi 0
    ~ < oi 128 {
        ( vec_push [u] outer_input # u & ( __sha512_vu8 opad oi ) 255 )
        = oi + oi 1
    }
    : ~ i ni 0
    ~ < ni 64 {
        ( vec_push [u] outer_input # u & ( __sha512_vu8 inner ni ) 255 )
        = ni + ni 1
    }
    : ( Vec u ) mac ( sha512_pure outer_input )
    ( vec_free [u] outer_input )
    ( vec_free [u] inner )
    ( vec_free [u] ipad )
    ( vec_free [u] opad )
    ( vec_free [u] kbuf )
    ^ mac
}
