// Test: incremental SHA-256 and BLAKE3 (init/update/final) — the
// streaming cores the one-shots are now built on. Proves (a) NIST /
// official vectors through awkward update splits, (b) equality with
// the one-shot for every tree-shape-relevant size and split, so the
// chunk/CV-stack bookkeeping cannot drift from the reference.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hash_blake3.nu`

@ ck b ok s name → v {
    ? ok { ( nurl_print `PASS ` ) } { ( nurl_print `FAIL ` ) }
    ( nurl_print name )
    ( nurl_print `\n` )
}

@ hex_is ( Vec u ) digest s want → b {
    : String hx ( bytes_to_hex digest )
    : b r ? ( nurl_str_eq ( string_data hx ) want ) T F
    ( string_free hx )
    ^ r
}

// deterministic pseudo-random-ish pattern, byte k = (k*131 + 7) & 255
@ pattern i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [u] v # u & + * k 131 7 255 )
        = k + k 1
    }
    ^ v
}

// stream `data` through updates of `step` bytes and finalize
@ sha_streamed ( Vec u ) data i step → ( Vec u ) {
    : *Sha256 h ( sha256_init )
    : i n ( vec_len [u] data )
    : ~ i off 0
    ~ < off n {
        : i take ? < - n off step - n off step
        : ( Vec u ) piece ( vec_with_cap [u] take )
        ( bytes_extend_raw piece # s + # i ( vec_data [u] data ) off take )
        ( sha256_update h piece )
        ( vec_free [u] piece )
        = off + off take
    }
    ^ ( sha256_final h )
}

@ b3_streamed ( Vec u ) data i step → ( Vec u ) {
    : *Blake3 h ( blake3_init )
    : i n ( vec_len [u] data )
    : ~ i off 0
    ~ < off n {
        : i take ? < - n off step - n off step
        : ( Vec u ) piece ( vec_with_cap [u] take )
        ( bytes_extend_raw piece # s + # i ( vec_data [u] data ) off take )
        ( blake3_update h piece )
        ( vec_free [u] piece )
        = off + off take
    }
    ^ ( blake3_final h )
}

@ eq_digest ( Vec u ) a ( Vec u ) b2 → b {
    ^ ( bytes_eq a b2 )
}

@ main → i {
    // ── SHA-256 vectors through the stream ──
    : *Sha256 h0 ( sha256_init )
    : ( Vec u ) d0 ( sha256_final h0 )
    ( ck ( hex_is d0 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` ) `sha256 stream: empty` )
    ( vec_free [u] d0 )

    : ( Vec u ) abc ( bytes_from_str `abc` )
    : ( Vec u ) d1 ( sha_streamed abc 1 )
    ( ck ( hex_is d1 `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` ) `sha256 stream: "abc" 1 B at a time` )
    ( vec_free [u] d1 )
    ( vec_free [u] abc )

    : ( Vec u ) two ( bytes_from_str `abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq` )
    : ( Vec u ) d2 ( sha_streamed two 13 )
    ( ck ( hex_is d2 `248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1` ) `sha256 stream: NIST 2-block, 13 B steps` )
    ( vec_free [u] d2 )
    ( vec_free [u] two )

    // splits that straddle the 64 B block edge == one-shot
    : ( Vec u ) big ( pattern 1000 )
    : ( Vec u ) ref ( sha256_pure big )
    : ~ b all T
    : steps [i | 1 63 64 65 129 999 1000]
    : *i SP . steps 0
    : ~ i si 0
    ~ < si 7 {
        : ( Vec u ) got ( sha_streamed big . SP si )
        ? ( eq_digest got ref ) {} { = all F }
        ( vec_free [u] got )
        = si + si 1
    }
    ( ck all `sha256 stream == one-shot across 7 split sizes` )
    ( vec_free [u] ref )
    ( vec_free [u] big )

    // ── BLAKE3 vectors + tree shapes ──
    : *Blake3 b0 ( blake3_init )
    : ( Vec u ) e0 ( blake3_final b0 )
    ( ck ( hex_is e0 `af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262` ) `blake3 stream: empty (official vector)` )
    ( vec_free [u] e0 )

    // every tree-shape-relevant size: sub-chunk, chunk edge, 2/3/5
    // chunks (odd stack folds), through three different split sizes
    : sizes [i | 1 1023 1024 1025 2048 3072 5000]
    : *i SZ . sizes 0
    : bsteps [i | 1 1024 700]
    : *i BS . bsteps 0
    : ~ b ball T
    : ~ i zi 0
    ~ < zi 7 {
        : ( Vec u ) datax ( pattern . SZ zi )
        : ( Vec u ) refx ( blake3_pure datax )
        : ~ i bi 0
        ~ < bi 3 {
            : ( Vec u ) gotx ( b3_streamed datax . BS bi )
            ? ( eq_digest gotx refx ) {} { = ball F }
            ( vec_free [u] gotx )
            = bi + bi 1
        }
        ( vec_free [u] refx )
        ( vec_free [u] datax )
        = zi + zi 1
    }
    ( ck ball `blake3 stream == one-shot: 7 sizes × 3 splits` )
    ^ 0
}
