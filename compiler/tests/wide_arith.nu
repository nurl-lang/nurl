// wide_arith.nu — the compiler's wide-arithmetic primitives
// (nurl_addc_lo/_hi, nurl_subb_lo/_hi, nurl_mac_lo/_hi, nurl_umulhi)
// against a reference built from 32-bit halves.
//
// These are the primitive under every big-number routine in the stdlib
// — P-256, X25519, Poly1305, RSA — so an off-by-one in a carry is a
// wrong signature, not a wrong number. The reference here deliberately
// shares no code with them: it splits each 64-bit operand into two
// 32-bit halves and does schoolbook arithmetic in which nothing can
// overflow, so it is checking the primitives rather than agreeing with
// them.

$ `stdlib/core/vec.nu`

: ~ i g_fail 0

@ chk s what u64 want u64 got → v {
    ? != want got {
        = g_fail + g_fail 1
        ? < g_fail 10 {
            ( nurl_print `FAIL ` ) ( nurl_print what )
            ( nurl_print ` want=` ) ( nurl_print_int # i want )
            ( nurl_print ` got=` ) ( nurl_println_int # i got )
            ( nurl_println `` )
        } {}
    } {}
}

// ── reference: 64×64→128 via four 32-bit partial products ────────────

@ ref_mulhi u64 a u64 b → u64 {
    : u64 al & a 4294967295
    : u64 ah >> a 32
    : u64 bl & b 4294967295
    : u64 bh >> b 32
    : u64 ll * al bl
    : u64 lh * al bh
    : u64 hl * ah bl
    : u64 hh * ah bh
    // mid = lh + hl + carry-out of the low halves; the sum of two
    // 32-bit-shifted products can carry into bit 64, so it is
    // accumulated in two pieces rather than one.
    : u64 mid + + >> ll 32 & lh 4294967295 & hl 4294967295
    ^ + + hh >> lh 32 + >> hl 32 >> mid 32
}

@ ref_addc_hi u64 a u64 b u64 c → u64 {
    : u64 s + a b
    : u64 c1 ? < s a 1 0
    : u64 t + s c
    : u64 c2 ? < t s 1 0
    ^ + c1 c2
}

@ ref_subb_hi u64 a u64 b u64 c → u64 {
    : u64 d - a b
    : u64 b1 ? < a b 1 0
    : u64 b2 ? < d c 1 0
    ^ | b1 b2
}

// A deterministic scrambler — the point is coverage of carry-boundary
// bit patterns, not statistical randomness, so a fixed 64-bit LCG-ish
// mixer is exactly right: same values on every platform, every run.
@ mix u64 x → u64 {
    : ~ u64 z + x 11400714819323198485
    = z * ^^ z >> z 30 13787848793156543929
    = z * ^^ z >> z 27 10723151780598845931
    ^ ^^ z >> z 31
}

@ main → i {
    // ── fixed edge cases ─────────────────────────────────────────────
    : u64 MAX 18446744073709551615
    ( chk `addc_lo max+1` 0 ( nurl_addc_lo MAX 1 0 ) )
    ( chk `addc_hi max+1` 1 ( nurl_addc_hi MAX 1 0 ) )
    ( chk `addc_lo max+0+1` 0 ( nurl_addc_lo MAX 0 1 ) )
    ( chk `addc_hi max+0+1` 1 ( nurl_addc_hi MAX 0 1 ) )
    ( chk `addc_lo max+max+1` MAX ( nurl_addc_lo MAX MAX 1 ) )
    ( chk `addc_hi max+max+1` 1 ( nurl_addc_hi MAX MAX 1 ) )
    ( chk `addc_hi 0+0+0` 0 ( nurl_addc_hi 0 0 0 ) )
    ( chk `subb_lo 0-1` MAX ( nurl_subb_lo 0 1 0 ) )
    ( chk `subb_hi 0-1` 1 ( nurl_subb_hi 0 1 0 ) )
    ( chk `subb_lo 0-0-1` MAX ( nurl_subb_lo 0 0 1 ) )
    ( chk `subb_hi 0-0-1` 1 ( nurl_subb_hi 0 0 1 ) )
    ( chk `subb_lo 0-max-1` 0 ( nurl_subb_lo 0 MAX 1 ) )
    ( chk `subb_hi 0-max-1` 1 ( nurl_subb_hi 0 MAX 1 ) )
    ( chk `subb_hi 5-3-1` 0 ( nurl_subb_hi 5 3 1 ) )
    ( chk `subb_lo 5-3-1` 1 ( nurl_subb_lo 5 3 1 ) )
    // max*max + max + max is the largest value the mac primitive must
    // hold: (2^64−1)^2 + 2(2^64−1) = 2^128 − 1, i.e. exactly full.
    ( chk `mac_lo saturate` MAX ( nurl_mac_lo MAX MAX MAX MAX ) )
    ( chk `mac_hi saturate` MAX ( nurl_mac_hi MAX MAX MAX MAX ) )
    ( chk `mac_lo 0` 0 ( nurl_mac_lo 0 0 0 0 ) )
    ( chk `mac_hi 0` 0 ( nurl_mac_hi 0 0 0 0 ) )
    ( chk `mac_lo 3*5+7+11` 33 ( nurl_mac_lo 3 5 7 11 ) )
    ( chk `mac_hi 3*5+7+11` 0 ( nurl_mac_hi 3 5 7 11 ) )

    // ── swept cases ──────────────────────────────────────────────────
    : ~ u64 x 1
    : ~ i it 0
    ~ < it 4000 {
        = x ( mix x )
        : u64 y ( mix ^^ x 12345678901234567 )
        : u64 c & x 1
        // umulhi and mac agree with the 32-bit-halves reference
        ( chk `umulhi` ( ref_mulhi x y ) ( nurl_umulhi x y ) )
        ( chk `mac_hi=umulhi when c=d=0` ( nurl_umulhi x y ) ( nurl_mac_hi x y 0 0 ) )
        ( chk `mac_lo=mul when c=d=0` * x y ( nurl_mac_lo x y 0 0 ) )
        // mac's own carry behaviour: adding c and d may carry into hi
        : u64 l1 ( nurl_mac_lo x y c 0 )
        : u64 h1 ( nurl_mac_hi x y c 0 )
        : u64 pl * x y
        : u64 ph ( nurl_umulhi x y )
        ( chk `mac_lo +c` ( nurl_addc_lo pl c 0 ) l1 )
        ( chk `mac_hi +c` ( nurl_addc_lo ph ( nurl_addc_hi pl c 0 ) 0 ) h1 )
        // addc / subb against the wrap-test reference
        ( chk `addc_lo` + + x y c ( nurl_addc_lo x y c ) )
        ( chk `addc_hi` ( ref_addc_hi x y c ) ( nurl_addc_hi x y c ) )
        ( chk `subb_lo` - - x y c ( nurl_subb_lo x y c ) )
        ( chk `subb_hi` ( ref_subb_hi x y c ) ( nurl_subb_hi x y c ) )
        // add then subtract the same operand restores the input, carry
        // and borrow cancelling
        : u64 s ( nurl_addc_lo x y 0 )
        : u64 sc ( nurl_addc_hi x y 0 )
        ( chk `add/sub roundtrip` x ( nurl_subb_lo s y 0 ) )
        ( chk `add/sub roundtrip borrow` sc ( nurl_subb_hi s y 0 ) )
        = it + it 1
    }

    // ── a 4-limb chain end to end: (2^256 − 1) + 1 == 2^256 ──────────
    : ( Vec u64 ) a ( vec_with_cap [u64] 4 )
    : ( Vec u64 ) b ( vec_with_cap [u64] 4 )
    : ~ i k 0
    ~ < k 4 { ( vec_push [u64] a MAX ) ( vec_push [u64] b ? == k 0 1 0 ) = k + k 1 }
    : *u64 ap ( vec_data [u64] a )
    : *u64 bp ( vec_data [u64] b )
    : u64 a0 . ap 0
    : u64 a1 . ap 1
    : u64 a2 . ap 2
    : u64 a3 . ap 3
    : u64 b0 . bp 0
    : u64 b1 . bp 1
    : u64 b2 . bp 2
    : u64 b3 . bp 3
    : u64 s0 ( nurl_addc_lo a0 b0 0 )
    : u64 c0 ( nurl_addc_hi a0 b0 0 )
    : u64 s1 ( nurl_addc_lo a1 b1 c0 )
    : u64 c1 ( nurl_addc_hi a1 b1 c0 )
    : u64 s2 ( nurl_addc_lo a2 b2 c1 )
    : u64 c2 ( nurl_addc_hi a2 b2 c1 )
    : u64 s3 ( nurl_addc_lo a3 b3 c2 )
    : u64 c3 ( nurl_addc_hi a3 b3 c2 )
    ( chk `chain limb0` 0 s0 )
    ( chk `chain limb1` 0 s1 )
    ( chk `chain limb2` 0 s2 )
    ( chk `chain limb3` 0 s3 )
    ( chk `chain carry out` 1 c3 )
    ( vec_free [u64] a )
    ( vec_free [u64] b )

    ? == g_fail 0 { ( nurl_println `wide arithmetic: primitives agree with the reference` ) }
    { ( nurl_print `wide arithmetic: ` ) ( nurl_print_int g_fail ) ( nurl_println ` mismatches` ) }
    ^ 0
}
