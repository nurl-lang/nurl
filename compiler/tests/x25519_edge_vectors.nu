// x25519_edge_vectors.nu — X25519 beyond RFC 7748's two vectors
// (x25519_vectors.nu): the RFC's 1000-iteration chain (§5.2), the inputs
// the RFC's vectors do not reach — u = 0, 1, p − 1, p, p + 1 and the
// order-8 point (each lands on 0 after the cofactor clamp), non-canonical
// u ≥ p, u with the top bit set — then a 200-step chain whose next point
// is mixed from the last result. Every line was checked against the RFC
// 7748 pseudocode run in Python big integers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/x25519.nu`

// 32 bytes, byte q = f(q)
@ gen32 i a i b i c i d → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 32 )
    : ~ i q 0
    ~ < q 32 { ( vec_push [u] v # u & ^^ + + * a q b c * d * q q 255 ) = q + q 1 }
    ^ v
}

@ byte_at ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ show s label ( Vec u ) r → v {
    : String h ( bytes_to_hex r )
    ( nurl_print label ) ( nurl_print ` ` ) ( nurl_print ( string_data h ) ) ( nurl_print `\n` )
    ( string_free h )
}

// the little-endian bytes of a 256-bit value given as four 64-bit words
@ le256 u64 w0 u64 w1 u64 w2 u64 w3 → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 32 )
    : ~ i q 0
    ~ < q 8 { ( vec_push [u] v # u & >> w0 * 8 q 255 ) = q + q 1 }
    = q 0
    ~ < q 8 { ( vec_push [u] v # u & >> w1 * 8 q 255 ) = q + q 1 }
    = q 0
    ~ < q 8 { ( vec_push [u] v # u & >> w2 * 8 q 255 ) = q + q 1 }
    = q 0
    ~ < q 8 { ( vec_push [u] v # u & >> w3 * 8 q 255 ) = q + q 1 }
    ^ v
}

@ main → i {
    : ~ ( Vec u ) k ( le256 # u64 9 # u64 0 # u64 0 # u64 0 )
    : ~ ( Vec u ) prev ( le256 # u64 9 # u64 0 # u64 0 # u64 0 )
    : ~ i n 0
    ~ < n 1000 {
        : ( Vec u ) r ( x25519 k prev )
        = prev k
        = k r
        = n + n 1
    }
    ( show `rfc7748_iter1000` k )

    // 0, 1, 2, p−1, p, p+1, p+18, 2^255−1, 2^256−1, the order-8 point
    : u64 m1 # u64 -1
    : u64 top 9223372036854775807
    : ( Vec ( Vec u ) ) pts ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] pts ( le256 # u64 0 # u64 0 # u64 0 # u64 0 ) )
    ( vec_push [( Vec u )] pts ( le256 # u64 1 # u64 0 # u64 0 # u64 0 ) )
    ( vec_push [( Vec u )] pts ( le256 # u64 2 # u64 0 # u64 0 # u64 0 ) )
    ( vec_push [( Vec u )] pts ( le256 # u64 -20 m1 m1 top ) )
    ( vec_push [( Vec u )] pts ( le256 # u64 -19 m1 m1 top ) )
    ( vec_push [( Vec u )] pts ( le256 # u64 -18 m1 m1 top ) )
    ( vec_push [( Vec u )] pts ( le256 # u64 -1 m1 m1 top ) )
    ( vec_push [( Vec u )] pts ( le256 m1 m1 m1 top ) )
    ( vec_push [( Vec u )] pts ( le256 m1 m1 m1 m1 ) )
    ( vec_push [( Vec u )] pts ( le256 # u64 -5856859591648023584 # u64 7693449925100787222 # u64 -166296061687821862 # u64 51872068454933126 ) )
    : ~ i j 0
    ~ < j 10 {
        : ( Vec u ) kk ( gen32 * 37 3 * 37 + * 7 j 1 0 0 )
        ?? ( vec_get [( Vec u )] pts j ) {
            T pt → { ( nurl_print `special` ) ( nurl_print_int j ) ( show `` ( x25519 kk pt ) ) }
            F _ → {}
        }
        = j + j 1
    }

    // the chain: point i mixes the previous result into a generated pattern
    : ~ ( Vec u ) acc ( le256 # u64 0 # u64 0 # u64 0 # u64 0 )
    : ~ i i 0
    ~ < i 200 {
        : ( Vec u ) kk ( gen32 29 + * i 131 5 0 1 )
        : ( Vec u ) uu ( vec_with_cap [u] 32 )
        : ~ i q 0
        ~ < q 32 { ( vec_push [u] uu # u & ^^ + + * i 17 * q 71 11 ( byte_at acc q ) 255 ) = q + q 1 }
        = acc ( x25519 kk uu )
        = i + i 1
    }
    ( show `chain200` acc )
    ^ 0
}
