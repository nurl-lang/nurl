// sha3_vectors.nu — FIPS 202 known-answer tests for SHA-3 and SHAKE.
//
// Digests and XOF outputs are pinned against Python's hashlib (which
// wraps the Keccak reference code). Beyond the plain digests, two
// properties get their own cases because ML-KEM depends on them:
//
//   * absorbing in arbitrary pieces equals absorbing in one go, across
//     a rate boundary;
//   * squeezing n bytes in small chunks equals squeezing them at once,
//     across a rate boundary — the rejection sampler in FIPS 203 pulls
//     three bytes at a time and must see one continuous stream.
//
// Multi-block XOF outputs are pinned by their SHA3-256 digest rather
// than 800 characters of literal hex; that checks every byte just as
// tightly and exercises a long absorb at the same time.

$ `stdlib/std/hash_sha3.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ check s label ( Vec u ) got_bytes s want → b {
    : String got ( bytes_to_hex got_bytes )
    : b ok != 0 ( nurl_str_eq ( string_data got ) want )
    ( nurl_print label ) ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ? ! ok {
        ( nurl_print `  got:  ` ) ( nurl_print ( string_data got ) ) ( nurl_print `\n` )
        ( nurl_print `  want: ` ) ( nurl_print want ) ( nurl_print `\n` )
    } {}
    ( string_free got )
    ^ ok
}

@ repeat_byte i b i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i i 0
    ~ < i n { ( vec_push [u] v # u b ) = i + i 1 }
    ^ v
}

// 0,1,2,…,255 repeated `reps` times — a long, non-uniform absorb.
@ seq_bytes i reps → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] * 256 reps )
    : ~ i r 0
    ~ < r reps {
        : ~ i i 0
        ~ < i 256 { ( vec_push [u] v # u i ) = i + i 1 }
        = r + r 1
    }
    ^ v
}

@ digest_of ( Vec u ) v → ( Vec u ) { ^ ( sha3_256_pure v ) }

@ main → i {
    : ~ b all T

    // ── SHA3-256: empty, short, and both sides of the 136-byte rate
    : ( Vec u ) e ( vec_new [u] )
    : ( Vec u ) d1 ( sha3_256_pure e )
    = all & all ( check `sha3-256 empty ` d1 `a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a` )
    ( vec_free [u] d1 )
    : ( Vec u ) d1b ( sha3_512_pure e )
    = all & all ( check `sha3-512 empty ` d1b `a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26` )
    ( vec_free [u] d1b )
    ( vec_free [u] e )

    : ( Vec u ) abc ( bytes_from_str `abc` )
    : ( Vec u ) d2 ( sha3_224_pure abc )
    = all & all ( check `sha3-224 abc   ` d2 `e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf` )
    ( vec_free [u] d2 )
    : ( Vec u ) d3 ( sha3_256_pure abc )
    = all & all ( check `sha3-256 abc   ` d3 `3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532` )
    ( vec_free [u] d3 )
    : ( Vec u ) d4 ( sha3_384_pure abc )
    = all & all ( check `sha3-384 abc   ` d4 `ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25` )
    ( vec_free [u] d4 )
    : ( Vec u ) d5 ( sha3_512_pure abc )
    = all & all ( check `sha3-512 abc   ` d5 `b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0` )
    ( vec_free [u] d5 )

    // 135 = rate-1, 136 = exactly the rate: the two padding edge cases
    : ( Vec u ) x135 ( repeat_byte 120 135 )
    : ( Vec u ) d6 ( sha3_256_pure x135 )
    = all & all ( check `sha3-256 135x  ` d6 `c150125edc74b56fb5cbfdd024fabe20ea5a99bd3c97305bbf7cb55885c106fe` )
    ( vec_free [u] d6 )
    ( vec_free [u] x135 )
    : ( Vec u ) x136 ( repeat_byte 120 136 )
    : ( Vec u ) d7 ( sha3_256_pure x136 )
    = all & all ( check `sha3-256 136x  ` d7 `5bc276bac9c582508b8fa9b3949e7ed9b6e584ee4d2925b29a426b9931ba1486` )
    ( vec_free [u] d7 )
    // SHAKE128's rate is 168 — check that boundary too
    : ( Vec u ) x168 ( repeat_byte 120 168 )
    : ( Vec u ) d8 ( sha3_512_pure x168 )
    = all & all ( check `sha3-512 168x  ` d8 `a35acbd20a71df3096fe54edc9eb5513810006c0da768e5f312b5cd1915d11f2f3737ab7876bbeb94a8a7232ca6bbf1d8e1390cf75ff7fc8ff4379ca1e92faaf` )
    ( vec_free [u] d8 )

    // ── SHAKE one-shot
    : ( Vec u ) s1 ( shake128_pure abc 32 )
    = all & all ( check `shake128 abc32 ` s1 `5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8` )
    ( vec_free [u] s1 )
    : ( Vec u ) s2 ( shake256_pure abc 64 )
    = all & all ( check `shake256 abc64 ` s2 `483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4` )
    ( vec_free [u] s2 )

    // ── Multi-block squeeze, pinned by the digest of the output.
    // 400 bytes is three SHAKE128 blocks; 1000 is eight SHAKE256 blocks.
    : ( Vec u ) s3 ( shake128_pure abc 400 )
    : ( Vec u ) h3 ( digest_of s3 )
    = all & all ( check `shake128 400b  ` h3 `019abfb8d7eef2c41da5d89ae9290661a1a9a5ed8061e6a282c803b73e1285a7` )
    ( vec_free [u] h3 )
    ( vec_free [u] s3 )
    : ( Vec u ) s4 ( shake256_pure abc 1000 )
    : ( Vec u ) h4 ( digest_of s4 )
    = all & all ( check `shake256 1000b ` h4 `c6ca244f2b23d7380518aea9a84a5000f35fb56777807d084c138e170cff7a75` )
    ( vec_free [u] h4 )
    ( vec_free [u] s4 )

    // ── Long absorb: 4352 bytes = 25 SHAKE128 blocks and change
    : ( Vec u ) seq ( seq_bytes 17 )
    : ( Vec u ) d9 ( sha3_256_pure seq )
    = all & all ( check `sha3-256 4352b ` d9 `21b18ad227a047874485a9d13e7063c1fc2396ac2aa82bf6ecfe856d65623f70` )
    ( vec_free [u] d9 )

    // ── Piecewise absorb == one-shot absorb.
    // Pieces of 1, 7 and 200 bytes cross lane and rate boundaries at
    // every alignment the fast path can see.
    : *Sha3 pa ( sha3_new 136 6 )
    : ~ i off 0
    : ~ i step 1
    : i seqn ( vec_len [u] seq )
    ~ < off seqn {
        : i take ? < + off step seqn step - seqn off
        : ( Vec u ) piece ( bytes_slice seq off + off take )
        ( sha3_absorb pa piece )
        ( vec_free [u] piece )
        = off + off take
        = step ? == step 1 7 ? == step 7 200 1
    }
    : ( Vec u ) d10 ( sha3_squeeze pa 32 )
    ( sha3_free pa )
    = all & all ( check `absorb pieces  ` d10 `21b18ad227a047874485a9d13e7063c1fc2396ac2aa82bf6ecfe856d65623f70` )
    ( vec_free [u] d10 )
    ( vec_free [u] seq )

    // ── Chunked squeeze == one-shot squeeze.
    // Three bytes at a time is exactly how FIPS 203 §7.3 samples the
    // public matrix, and 400 bytes crosses two rate boundaries.
    : *Sha3 px ( shake128_init )
    ( sha3_absorb px abc )
    : ( Vec u ) acc ( vec_new [u] )
    : ~ i got 0
    ~ < got 400 {
        : i want ? < + got 3 400 3 - 400 got
        : ( Vec u ) chunk ( sha3_squeeze px want )
        ( bytes_extend_bytes acc chunk )
        ( vec_free [u] chunk )
        = got + got want
    }
    ( sha3_free px )
    : ( Vec u ) h5 ( digest_of acc )
    = all & all ( check `squeeze by 3   ` h5 `019abfb8d7eef2c41da5d89ae9290661a1a9a5ed8061e6a282c803b73e1285a7` )
    ( vec_free [u] h5 )
    ( vec_free [u] acc )
    ( vec_free [u] abc )
    ( vec_free [u] x136 )
    ( vec_free [u] x168 )

    ^ ? all 0 1
}
