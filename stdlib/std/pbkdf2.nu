// stdlib/std/pbkdf2.nu — PBKDF2-HMAC-SHA-256 (RFC 8018 §5.2) in pure NURL.
//
//   ( pbkdf2_hmac_sha256 password salt iters dklen ) → ( Vec u )  dklen bytes
//
// `password` and `salt` are ( Vec u ); `iters` is the iteration count and
// `dklen` the desired derived-key length in bytes. Built on the pure-NURL
// HMAC-SHA-256 — no OpenSSL/FFI. This is the key-stretching primitive used
// by SCRAM-SHA-256 (RFC 7677), where dklen is 32 (one HMAC block).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hash_sha512.nu`

@ __pb_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// One PBKDF2 block F(P, S, c, i) = U_1 ^ U_2 ^ ... ^ U_c, each U_n a
// 32-byte HMAC-SHA-256. U_1 = HMAC(P, S || INT32-BE(i)); U_n = HMAC(P, U_{n-1}).
@ __pb_block ( Vec u ) password ( Vec u ) salt i iters i blockidx → ( Vec u ) {
    : i slen ( vec_len [u] salt )
    : ( Vec u ) seed ( vec_with_cap [u] + slen 4 )
    : ~ i si 0
    ~ < si slen { ( vec_push [u] seed # u ( __pb_bget salt si ) ) = si + si 1 }
    ( vec_push [u] seed # u & >> blockidx 24 255 )
    ( vec_push [u] seed # u & >> blockidx 16 255 )
    ( vec_push [u] seed # u & >> blockidx 8 255 )
    ( vec_push [u] seed # u & blockidx 255 )

    : ~ ( Vec u ) u ( hmac_sha256_pure password seed )
    ( vec_free [u] seed )

    // accumulator t starts as a copy of U_1
    : ( Vec u ) t ( vec_with_cap [u] 32 )
    : ~ i ti 0
    ~ < ti 32 { ( vec_push [u] t # u ( __pb_bget u ti ) ) = ti + ti 1 }

    : ~ i n 1
    ~ < n iters {
        : ( Vec u ) un ( hmac_sha256_pure password u )
        ( vec_free [u] u )
        = u un
        : ~ i xi 0
        ~ < xi 32 {
            : i cur ?? ( vec_get [u] t xi ) { T x → # i x F _ → 0 }
            ( vec_set [u] t xi # u & ^^ cur ( __pb_bget u xi ) 255 )
            = xi + xi 1
        }
        = n + n 1
    }
    ( vec_free [u] u )
    ^ t
}

@ pbkdf2_hmac_sha256 ( Vec u ) password ( Vec u ) salt i iters i dklen → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] ? > dklen 0 dklen 1 )
    : ~ i blockidx 1
    : ~ i generated 0
    ~ < generated dklen {
        : ( Vec u ) blk ( __pb_block password salt iters blockidx )
        : i take ? > - dklen generated 32 32 - dklen generated
        : ~ i bi 0
        ~ < bi take { ( vec_push [u] out # u ( __pb_bget blk bi ) ) = bi + bi 1 }
        ( vec_free [u] blk )
        = generated + generated take
        = blockidx + blockidx 1
    }
    ^ out
}

// ── PBKDF2-HMAC-SHA-512 (RFC 8018, 64-byte HMAC blocks) ────────────
@ __pb_block512 ( Vec u ) password ( Vec u ) salt i iters i blockidx → ( Vec u ) {
    : i slen ( vec_len [u] salt )
    : ( Vec u ) seed ( vec_with_cap [u] + slen 4 )
    : ~ i si 0
    ~ < si slen { ( vec_push [u] seed # u ( __pb_bget salt si ) ) = si + si 1 }
    ( vec_push [u] seed # u & >> blockidx 24 255 )
    ( vec_push [u] seed # u & >> blockidx 16 255 )
    ( vec_push [u] seed # u & >> blockidx 8 255 )
    ( vec_push [u] seed # u & blockidx 255 )

    : ~ ( Vec u ) u ( hmac_sha512_pure password seed )
    ( vec_free [u] seed )

    : ( Vec u ) t ( vec_with_cap [u] 64 )
    : ~ i ti 0
    ~ < ti 64 { ( vec_push [u] t # u ( __pb_bget u ti ) ) = ti + ti 1 }

    : ~ i n 1
    ~ < n iters {
        : ( Vec u ) un ( hmac_sha512_pure password u )
        ( vec_free [u] u )
        = u un
        : ~ i xi 0
        ~ < xi 64 {
            : i cur ?? ( vec_get [u] t xi ) { T x → # i x F _ → 0 }
            ( vec_set [u] t xi # u & ^^ cur ( __pb_bget u xi ) 255 )
            = xi + xi 1
        }
        = n + n 1
    }
    ( vec_free [u] u )
    ^ t
}

@ pbkdf2_hmac_sha512 ( Vec u ) password ( Vec u ) salt i iters i dklen → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] ? > dklen 0 dklen 1 )
    : ~ i blockidx 1
    : ~ i generated 0
    ~ < generated dklen {
        : ( Vec u ) blk ( __pb_block512 password salt iters blockidx )
        : i take ? > - dklen generated 64 64 - dklen generated
        : ~ i bi 0
        ~ < bi take { ( vec_push [u] out # u ( __pb_bget blk bi ) ) = bi + bi 1 }
        ( vec_free [u] blk )
        = generated + generated take
        = blockidx + blockidx 1
    }
    ^ out
}
