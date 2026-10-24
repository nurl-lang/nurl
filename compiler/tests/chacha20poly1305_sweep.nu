// chacha20poly1305_sweep.nu — the in-place AEAD (chacha20poly1305_seal_in
// / _open_in, the TLS record path) over every message length from 0 to
// 1100 bytes and a few at 4 KB and 16 KB, each with no AAD and with 13
// bytes of it, the sequence number following the length. Poly1305 runs
// four blocks at a time from 256 bytes of MAC input (where the CPU has
// 256-bit vectors) with one 64-byte group or many, an odd count or an
// even one, and a scalar tail of any length; below that, the scalar
// blocks alone — so the sweep crosses every seam between the two. Each
// sealed record is folded into a SHA-256 chain whose golden comes from
// an independent RFC 8439 implementation in Python; each one must also
// open back to its plaintext, and a record with one bit of its tag
// flipped must not.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/chacha20poly1305.nu`

// n bytes, byte k = ((k·131 + salt·29 + 7) xor (k >> 3)) & 255
@ pat i n i salt → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u & ^^ + + * k 131 * salt 29 7 >> k 3 255 ) = k + k 1 }
    ^ v
}

: ~ i g_fails 0

// One record sealed, folded into the chain `acc` (returned), and opened.
@ record ( Vec u ) acc ( Vec u ) key ( Vec u ) iv i len i alen → ( Vec u ) {
    : ( Vec u ) aad ( pat alen 1 )
    : ( Vec u ) msg ( pat len 2 )
    : ( Vec u ) buf ( vec_with_cap [u] + alen len )
    ( bytes_extend_bytes buf aad )
    ( bytes_extend_bytes buf msg )
    : ~ b ok ( chacha20poly1305_seal_in key iv len buf 0 alen )
    : ( Vec u ) both ( vec_with_cap [u] + 32 ( vec_len [u] buf ) )
    ( bytes_extend_bytes both acc )
    ( bytes_extend_bytes both buf )
    : ( Vec u ) next ( sha256_pure both )
    // a flipped tag bit must not open (and leaves the range zeroed)
    : ( Vec u ) bad ( bytes_slice buf 0 ( vec_len [u] buf ) )
    : i last - ( vec_len [u] bad ) 1
    ( vec_set [u] bad last # u ^^ ?? ( vec_get [u] bad last ) { T x → # i x F _ → 0 } 1 )
    = ok & ok ! ( chacha20poly1305_open_in key iv len bad 0 alen ( vec_len [u] bad ) )
    = ok & ok ( chacha20poly1305_open_in key iv len buf 0 alen ( vec_len [u] buf ) )
    = ok & ok ( bytes_eq ( bytes_slice buf alen + alen len ) msg )
    ? ! ok {
        ( nurl_print `FAIL len=` ) ( nurl_print_int len ) ( nurl_print ` aad=` ) ( nurl_print_int alen ) ( nurl_print `\n` )
        = g_fails + g_fails 1
    } {}
    ^ next
}

@ main → i {
    : ( Vec u ) key ( vec_with_cap [u] 32 )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] key # u & + * k 7 1 255 ) = k + k 1 }
    : ( Vec u ) iv ( vec_with_cap [u] 12 )
    = k 0
    ~ < k 12 { ( vec_push [u] iv # u & + k 3 255 ) = k + k 1 }
    : ~ ( Vec u ) acc ( vec_zeroed [u] 32 )
    : ( Vec i ) lens ( vec_new [i] )
    = k 0
    ~ <= k 1100 { ( vec_push [i] lens k ) = k + k 1 }
    ( vec_push [i] lens 4095 )
    ( vec_push [i] lens 4096 )
    ( vec_push [i] lens 4097 )
    ( vec_push [i] lens 16383 )
    ( vec_push [i] lens 16384 )
    ( vec_push [i] lens 16399 )
    : ~ i n 0
    = k 0
    ~ < k ( vec_len [i] lens ) {
        : i len ?? ( vec_get [i] lens k ) { T x → x F _ → 0 }
        = acc ( record acc key iv len 0 )
        = acc ( record acc key iv len 13 )
        = n + n 2
        = k + k 1
    }
    ( nurl_print `sweep: ` ) ( nurl_print_int n ) ( nurl_print ` records, ` )
    ( nurl_print_int g_fails ) ( nurl_print ` failures\n` )
    : String h ( bytes_to_hex acc )
    ( nurl_print `chain ` ) ( nurl_print ( string_data h ) ) ( nurl_print `\n` )
    ( string_free h )
    ^ ? == g_fails 0 0 1
}
