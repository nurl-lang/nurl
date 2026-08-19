// stdlib/std/hash_sha3x4.nu against stdlib/std/hash_sha3.nu, one lane
// at a time.
//
// The four-way sponge has no vectors of its own to check against: NIST
// publishes SHAKE, not SHAKE-times-four. But the four ways are
// independent by construction — nothing in the permutation crosses a
// lane — so the correct oracle is the scalar sponge that IS covered by
// NIST vectors (compiler/tests/sha3_vectors.nu), run four times.
//
// That makes this a differential test in the strong sense: an error in
// the interleave, in a rotation constant, in a round constant, or in
// the ping-pong parity shows up as one lane disagreeing with a sponge
// the vectors already vouch for. A shared bug is impossible — the two
// implementations have no code in common except the round-constant
// table, which is deliberately shared for exactly that reason.
//
// The lanes are given DIFFERENT inputs on purpose. Four identical
// inputs would pass even if the permutation broadcast lane 0 over all
// four ways, which is the single most likely way to get the interleave
// wrong.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_sha3.nu`
$ `stdlib/std/hash_sha3x4.nu`

: ~ i g_fail 0

@ __mk i n i seed → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i i 0
    ~ < i n { ( vec_push [u] v & 255 + seed * i 31 ) = i + i 1 }
    ^ v
}

@ __eq ( Vec u ) a ( Vec u ) b → b {
    ? != ( vec_len [u] a ) ( vec_len [u] b ) { ^ F } {}
    : ~ i i 0
    ~ < i ( vec_len [u] a ) {
        ? != # i . ( vec_data [u] a ) i # i . ( vec_data [u] b ) i { ^ F } {}
        = i + i 1
    }
    ^ T
}

@ __report s label b ok → v {
    ( nurl_print label )
    ? ok { ( nurl_print ` ok\n` ) } { ( nurl_print ` FAIL\n` ) = g_fail + g_fail 1 }
}

// One case: absorb `inlen` distinct bytes into each way, squeeze
// `outlen`, and compare each way against the scalar sponge.
@ __case s label i rate i dom i inlen i outlen → v {
    : ( Vec u ) d0 ( __mk inlen 1 )
    : ( Vec u ) d1 ( __mk inlen 77 )
    : ( Vec u ) d2 ( __mk inlen 140 )
    : ( Vec u ) d3 ( __mk inlen 211 )

    : *Sha3x4 hx ( sha3x4_new rate dom )
    ( sha3x4_absorb hx d0 d1 d2 d3 )
    : ( Vec u ) o0 ( vec_new [u] )
    : ( Vec u ) o1 ( vec_new [u] )
    : ( Vec u ) o2 ( vec_new [u] )
    : ( Vec u ) o3 ( vec_new [u] )
    ( sha3x4_squeeze hx outlen o0 o1 o2 o3 )
    ( sha3x4_free hx )

    : *Sha3 s0 ( sha3_new rate dom ) ( sha3_absorb s0 d0 )
    : ( Vec u ) e0 ( sha3_squeeze s0 outlen ) ( sha3_free s0 )
    : *Sha3 s1 ( sha3_new rate dom ) ( sha3_absorb s1 d1 )
    : ( Vec u ) e1 ( sha3_squeeze s1 outlen ) ( sha3_free s1 )
    : *Sha3 s2 ( sha3_new rate dom ) ( sha3_absorb s2 d2 )
    : ( Vec u ) e2 ( sha3_squeeze s2 outlen ) ( sha3_free s2 )
    : *Sha3 s3 ( sha3_new rate dom ) ( sha3_absorb s3 d3 )
    : ( Vec u ) e3 ( sha3_squeeze s3 outlen ) ( sha3_free s3 )

    : b ok & & & ( __eq o0 e0 ) ( __eq o1 e1 ) ( __eq o2 e2 ) ( __eq o3 e3 )
    ( __report label ok )
    // The lanes must also DIFFER from each other. If they did not, an
    // implementation that broadcast one way over all four would pass
    // every comparison above. Empty input is exempt and not a special
    // case being waved through: with nothing absorbed the four sponges
    // ARE the same sponge, and four equal outputs is the right answer.
    ? & ok > inlen 0 {
        ? ( __eq o0 o1 ) { ( nurl_print `  lanes identical — inputs did not separate\n` ) = g_fail + g_fail 1 } {}
    } {}

    ( vec_free [u] d0 ) ( vec_free [u] d1 ) ( vec_free [u] d2 ) ( vec_free [u] d3 )
    ( vec_free [u] o0 ) ( vec_free [u] o1 ) ( vec_free [u] o2 ) ( vec_free [u] o3 )
    ( vec_free [u] e0 ) ( vec_free [u] e1 ) ( vec_free [u] e2 ) ( vec_free [u] e3 )
}

// Absorbing in several pieces must equal absorbing in one — the
// property the block-straddling path exists to provide, and the one a
// per-way `pos` would break.
@ __case_pieces → v {
    : ( Vec u ) a0 ( __mk 100 3 ) : ( Vec u ) a1 ( __mk 100 51 )
    : ( Vec u ) a2 ( __mk 100 99 ) : ( Vec u ) a3 ( __mk 100 160 )
    : ( Vec u ) b0 ( __mk 100 7 ) : ( Vec u ) b1 ( __mk 100 55 )
    : ( Vec u ) b2 ( __mk 100 103 ) : ( Vec u ) b3 ( __mk 100 164 )

    : *Sha3x4 h ( shake128x4_init )
    ( sha3x4_absorb h a0 a1 a2 a3 )
    ( sha3x4_absorb h b0 b1 b2 b3 )
    : ( Vec u ) o0 ( vec_new [u] ) : ( Vec u ) o1 ( vec_new [u] )
    : ( Vec u ) o2 ( vec_new [u] ) : ( Vec u ) o3 ( vec_new [u] )
    // Squeeze in two calls too: the stream must continue, not restart.
    ( sha3x4_squeeze h 40 o0 o1 o2 o3 )
    ( sha3x4_squeeze h 160 o0 o1 o2 o3 )
    ( sha3x4_free h )

    : *Sha3 r0 ( shake128_init ) ( sha3_absorb r0 a0 ) ( sha3_absorb r0 b0 )
    : ( Vec u ) e0 ( sha3_squeeze r0 200 ) ( sha3_free r0 )
    : *Sha3 r3 ( shake128_init ) ( sha3_absorb r3 a3 ) ( sha3_absorb r3 b3 )
    : ( Vec u ) e3 ( sha3_squeeze r3 200 ) ( sha3_free r3 )

    ( __report `pieces+resume  ` & ( __eq o0 e0 ) ( __eq o3 e3 ) )

    ( vec_free [u] a0 ) ( vec_free [u] a1 ) ( vec_free [u] a2 ) ( vec_free [u] a3 )
    ( vec_free [u] b0 ) ( vec_free [u] b1 ) ( vec_free [u] b2 ) ( vec_free [u] b3 )
    ( vec_free [u] o0 ) ( vec_free [u] o1 ) ( vec_free [u] o2 ) ( vec_free [u] o3 )
    ( vec_free [u] e0 ) ( vec_free [u] e3 )
}

// Unequal input lengths are a contract violation and must not leave the
// sponge in a half-absorbed state: the four ways stay where they were,
// so the result equals absorbing nothing at all.
@ __case_unequal → v {
    : ( Vec u ) d0 ( __mk 32 1 ) : ( Vec u ) d1 ( __mk 33 2 )
    : ( Vec u ) d2 ( __mk 32 3 ) : ( Vec u ) d3 ( __mk 32 4 )
    : *Sha3x4 h ( shake256x4_init )
    ( sha3x4_absorb h d0 d1 d2 d3 )
    : ( Vec u ) o0 ( vec_new [u] ) : ( Vec u ) o1 ( vec_new [u] )
    : ( Vec u ) o2 ( vec_new [u] ) : ( Vec u ) o3 ( vec_new [u] )
    ( sha3x4_squeeze h 32 o0 o1 o2 o3 )
    ( sha3x4_free h )

    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) e ( shake256_pure empty 32 )
    ( __report `unequal rejected` ( __eq o0 e ) )

    ( vec_free [u] d0 ) ( vec_free [u] d1 ) ( vec_free [u] d2 ) ( vec_free [u] d3 )
    ( vec_free [u] o0 ) ( vec_free [u] o1 ) ( vec_free [u] o2 ) ( vec_free [u] o3 )
    ( vec_free [u] empty ) ( vec_free [u] e )
}

@ main → v {
    // Input lengths chosen around the block boundaries the two rates
    // have: 168 for SHAKE128, 136 for SHAKE256. Empty, short, exactly
    // one block, one past a block, several blocks.
    ( __case `shake128 in=0   ` 168 31 0 32 )
    ( __case `shake128 in=1   ` 168 31 1 32 )
    ( __case `shake128 in=167 ` 168 31 167 32 )
    ( __case `shake128 in=168 ` 168 31 168 32 )
    ( __case `shake128 in=169 ` 168 31 169 32 )
    ( __case `shake128 in=512 ` 168 31 512 32 )
    // Outputs that straddle a squeeze block, which is where a shared
    // `pos` and a per-way one part company.
    ( __case `shake128 out=167` 168 31 34 167 )
    ( __case `shake128 out=168` 168 31 34 168 )
    ( __case `shake128 out=504` 168 31 34 504 )
    ( __case `shake256 in=135 ` 136 31 135 64 )
    ( __case `shake256 in=136 ` 136 31 136 64 )
    ( __case `shake256 out=300` 136 31 66 300 )
    // The SHA-3 domain byte, not just SHAKE's.
    ( __case `sha3-256 dom=6  ` 136 6 100 32 )
    ( __case `sha3-512 dom=6  ` 72 6 200 64 )
    ( __case_pieces )
    ( __case_unequal )

    ? == g_fail 0 { ( nurl_print `sha3x4: all lanes agree with the scalar sponge\n` ) }
    { ( nurl_print `sha3x4: ` ) ( nurl_print ( nurl_str_int g_fail ) )
        ( nurl_print ` FAILURES\n` ) }
}
