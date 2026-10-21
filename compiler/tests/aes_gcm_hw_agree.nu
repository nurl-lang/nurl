// aes_gcm_hw_agree.nu — the hardware AES-GCM path (AES-NI + PCLMULQDQ,
// std/aes_gcm.nu) against the software one, in one process.
//
// Every message length from 0 to 300 bytes walks every path through
// the hardware kernel: the eight-block stitched loop (none, one, two
// steps), the single blocks after it and a short last block, with AAD
// of 0 to 37 bytes (none, a short block, more than two blocks) and
// both key sizes. The software key is the oracle — its own vectors are
// aes_gcm_vectors.nu — so a wrong carry in the reflected GHASH, a
// counter that does not wrap like inc32, or a mis-sized tail shows up
// as a differing byte. Each sealed message is also opened by the OTHER
// key, and a flipped tag bit must fail on both.
//
// requires: cpu-aes
//
// On a CPU without the crypto tier both keys are software and the test
// still passes: it then proves nothing about the hardware path, which
// is why the golden records which path ran.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/aes_gcm.nu`

// xorshift64: deterministic bytes, no dependency on a RNG module.
@ next u64 x → u64 {
    : ~ u64 y x
    = y ^^ y << y 13
    = y ^^ y >> y 7
    = y ^^ y << y 17
    ^ y
}

@ fill i n u64 seed → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ u64 s seed
    : ~ i k 0
    ~ < k n { = s ( next s ) ( vec_push [u] v # u & # i s 255 ) = k + k 1 }
    ^ v
}

@ same ( Vec u ) a ( Vec u ) b → b {
    ? != ( vec_len [u] a ) ( vec_len [u] b ) { ^ F } {}
    : ~ i k 0
    ~ < k ( vec_len [u] a ) { ? != ( vec_at [u] a k ) ( vec_at [u] b k ) { ^ F } {} = k + k 1 }
    ^ T
}

@ opens AesGcmKey k ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct ( Vec u ) pt → b {
    ?? ( aes_gcm_open k nonce aad ct ) { T p → ^ ( same p pt ) F _ → ^ F }
}

@ rejects AesGcmKey k ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct → b {
    ?? ( aes_gcm_open k nonce aad ct ) { T p → ^ F F _ → ^ T }
}

@ main → i {
    ? ( nurl_cpu_has_aes ) { ( nurl_print `path: hardware vs software\n` ) } { ( nurl_print `path: software vs software (no crypto tier)\n` ) }
    : ~ i fails 0
    : ~ i cases 0
    : ~ i klen 16
    ~ <= klen 32 {
        : ( Vec u ) key ( fill klen # u64 + 1000 klen )
        : AesGcmKey hw ( aes_gcm_key_new key )
        : AesGcmKey sw ( _aes_gcm_key_sw key )
        : ~ i n 0
        ~ <= n 300 {
            : i alen % * n 7 38
            : ( Vec u ) nonce ( fill 12 # u64 + 77 n )
            : ( Vec u ) aad ( fill alen # u64 + 5000 n )
            : ( Vec u ) pt ( fill n # u64 + 9000 n )
            : ( Vec u ) c1 ( aes_gcm_seal hw nonce aad pt )
            : ( Vec u ) c2 ( aes_gcm_seal sw nonce aad pt )
            ? ! ( same c1 c2 ) {
                ( nurl_print `seal differs: klen ` ) ( nurl_print ( nurl_str_int klen ) )
                ( nurl_print ` n ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
                = fails + fails 1
            } {}
            ? ! & ( opens sw nonce aad c1 pt ) ( opens hw nonce aad c2 pt ) {
                ( nurl_print `open failed: n ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
                = fails + fails 1
            } {}
            // Flip one tag bit: both keys must refuse it.
            : ( Vec u ) bad ( fill 0 0 )
            ( bytes_extend_bytes bad c1 )
            : i last - ( vec_len [u] bad ) 1
            ( vec_put [u] bad last # u ^^ # i ( vec_at [u] bad last ) 1 )
            ? ! & ( rejects hw nonce aad bad ) ( rejects sw nonce aad bad ) {
                ( nurl_print `tamper accepted: n ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
                = fails + fails 1
            } {}
            = cases + cases 1
            = n + n 1
        }
        // One raw block (QUIC header protection) on both keys.
        : ( Vec u ) blk ( fill 16 # u64 31337 )
        ? ! ( same ( aes_block_encrypt hw blk ) ( aes_block_encrypt sw blk ) ) {
            ( nurl_print `block differs\n` ) = fails + fails 1
        } {}
        = klen + klen 16
    }
    ( nurl_print `cases ` ) ( nurl_print ( nurl_str_int cases ) )
    ( nurl_print `, failures ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print `\n` )
    ^ fails
}
