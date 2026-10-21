// aead_in_place.nu — the record layer's in-place AEADs
// (aes_gcm_seal_in / aes_gcm_open_in, chacha20poly1305_seal_in /
// chacha20poly1305_open_in) against the Vec APIs they must agree with.
//
// Every record sits inside a buffer with unrelated bytes before its AAD
// and, when opened, after its tag — as in a socket buffer holding the
// next record — and those bytes must come back untouched. Lengths walk
// 0..300 so the AES path takes its eight-block steps, its tail of zero
// to eight blocks and a short last block, and ChaCha20 its wide, two-
// block and one-block passes; the AES key is tried on the hardware
// path and on the software one (which, opening in place, must take the
// tag before the CTR pass overwrites the ciphertext). A flipped tag bit
// must fail and leave the plaintext range zeroed.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/aes_gcm.nu`
$ `stdlib/std/chacha20poly1305.nu`

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

@ same_at ( Vec u ) a i aoff ( Vec u ) b i boff i n → b {
    : ~ i k 0
    ~ < k n { ? != ( vec_at [u] a + aoff k ) ( vec_at [u] b + boff k ) { ^ F } {} = k + k 1 }
    ^ T
}

@ seq_nonce ( Vec u ) iv i seq → ( Vec u ) {
    : ( Vec u ) n ( vec_zeroed [u] 12 )
    : ~ i b 0
    ~ < b 12 {
        : i sb ? < b 4 0 & >> seq * 8 - 11 b 255
        ( vec_put [u] n b # u ^^ # i ( vec_at [u] iv b ) sb )
        = b + b 1
    }
    ^ n
}

// cipher 0 = ChaCha20-Poly1305, 1 = AES-GCM under `gk`.
@ seal_in i cipher AesGcmKey gk ( Vec u ) key ( Vec u ) iv i seq ( Vec u ) buf i aad_at i data_at → b {
    ? == cipher 1 { ^ ( aes_gcm_seal_in gk iv seq buf aad_at data_at ) } {}
    ^ ( chacha20poly1305_seal_in key iv seq buf aad_at data_at )
}

@ open_in i cipher AesGcmKey gk ( Vec u ) key ( Vec u ) iv i seq ( Vec u ) buf i aad_at i data_at i end → b {
    ? == cipher 1 { ^ ( aes_gcm_open_in gk iv seq buf aad_at data_at end ) } {}
    ^ ( chacha20poly1305_open_in key iv seq buf aad_at data_at end )
}

@ seal_vec i cipher AesGcmKey gk ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → ( Vec u ) {
    ? == cipher 1 { ^ ( aes_gcm_seal gk nonce aad pt ) } {}
    ^ ( aead_encrypt key nonce aad pt )
}

// One (cipher, key, n, alen) case; the count of what went wrong.
@ one i cipher AesGcmKey gk ( Vec u ) key i n i alen → i {
    : ~ i bad 0
    : ( Vec u ) iv ( fill 12 # u64 + 41 n )
    : i seq + * n 977 * alen 13
    : ( Vec u ) pre ( fill 7 # u64 3 )
    : ( Vec u ) aad ( fill alen # u64 + 500 alen )
    : ( Vec u ) pt ( fill n # u64 + 900 n )
    : ( Vec u ) post ( fill 9 # u64 77 )
    : ( Vec u ) want ( seal_vec cipher gk key ( seq_nonce iv seq ) aad pt )

    : ( Vec u ) buf ( vec_new [u] )
    ( bytes_extend_bytes buf pre )
    ( bytes_extend_bytes buf aad )
    ( bytes_extend_bytes buf pt )
    : i aad_at ( vec_len [u] pre )
    : i data_at + aad_at alen
    ? ! ( seal_in cipher gk key iv seq buf aad_at data_at ) { = bad + bad 1 } {}
    ? | != ( vec_len [u] buf ) + data_at + n 16 ! ( same_at buf data_at want 0 + n 16 ) { = bad + bad 1 } {}
    ? ! & ( same_at buf 0 pre 0 aad_at ) ( same_at buf aad_at aad 0 alen ) { = bad + bad 1 } {}

    // Open with the next record's bytes behind it.
    : i end ( vec_len [u] buf )
    ( bytes_extend_bytes buf post )
    : ( Vec u ) sealed ( bytes_slice buf 0 ( vec_len [u] buf ) )
    ? ! ( open_in cipher gk key iv seq buf aad_at data_at end ) { = bad + bad 1 } {}
    ? ! ( same_at buf data_at pt 0 n ) { = bad + bad 1 } {}
    ? ! ( same_at buf end post 0 9 ) { = bad + bad 1 } {}

    // A flipped tag bit: refused, plaintext range zeroed, the rest intact.
    : i last - end 1
    ( vec_put [u] sealed last # u ^^ # i ( vec_at [u] sealed last ) 1 )
    ? ( open_in cipher gk key iv seq sealed aad_at data_at end ) { = bad + bad 1 } {}
    : ~ i k 0
    ~ < k n { ? != ( vec_at [u] sealed + data_at k ) 0 { = bad + bad 1 = k n } {} = k + k 1 }
    ? ! ( same_at sealed end post 0 9 ) { = bad + bad 1 } {}
    ^ bad
}

@ main → i {
    : ~ i fails 0
    : ~ i cases 0
    : ( Vec u ) k32 ( fill 32 # u64 7 )
    : ( Vec u ) k16 ( fill 16 # u64 8 )
    : AesGcmKey hw ( aes_gcm_key_new k16 )
    : AesGcmKey sw ( _aes_gcm_key_sw k16 )
    : ~ i n 0
    ~ <= n 300 {
        : i alen % * n 7 38
        : i f0 ( one 0 hw k32 n alen )
        : i f1 ( one 1 hw k32 n alen )
        : i f2 ( one 1 sw k32 n alen )
        ? != + + f0 f1 f2 0 {
            ( nurl_print `differs: n ` ) ( nurl_print ( nurl_str_int n ) )
            ( nurl_print ` chacha ` ) ( nurl_print ( nurl_str_int f0 ) )
            ( nurl_print ` gcm-hw ` ) ( nurl_print ( nurl_str_int f1 ) )
            ( nurl_print ` gcm-sw ` ) ( nurl_print ( nurl_str_int f2 ) ) ( nurl_print `\n` )
            = fails + fails 1
        } {}
        = cases + cases 3
        = n + n 1
    }
    ( nurl_print `cases ` ) ( nurl_print ( nurl_str_int cases ) )
    ( nurl_print `, failures ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print `\n` )
    ^ fails
}
