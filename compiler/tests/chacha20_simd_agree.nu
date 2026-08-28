// chacha20_simd_agree.nu — the vector ChaCha20 kernel must produce
// byte-identical output to the scalar reference, for every length.
//
// RFC 8439's test vectors pin two lengths. The failures a blocked
// vector kernel actually has are at the seams the vectors never touch:
// the two-block fast path handing over to the one-block path, that
// handing over to the byte tail, and the block counter having to keep
// counting across all three. So this walks every length from 0 to 300 —
// crossing 64, 128, 192 and 256 by construction — at two different
// starting counters and a non-zero data offset, and compares every byte.

$ `stdlib/core/vec.nu`
$ `stdlib/std/chacha20poly1305.nu`

: ~ i g_bad 0

@ sweep i counter i doff → v {
    : ( Vec u ) key ( vec_with_cap [u] 32 )
    : ( Vec u ) non ( vec_with_cap [u] 12 )
    : b _a ( vec_set_len [u] key 32 )
    : b _b ( vec_set_len [u] non 12 )
    : *u kp ( vec_data [u] key )
    : *u np ( vec_data [u] non )
    : ~ i k 0
    ~ < k 32 { = . kp k # u & 255 + * k 7 counter = k + k 1 }
    = k 0
    ~ < k 12 { = . np k # u & 255 + k 3 = k + k 1 }

    : ~ i n 0
    ~ <= n 300 {
        : i total + n doff
        : ( Vec u ) dat ( vec_with_cap [u] ? > total 0 total 1 )
        : b _c ( vec_set_len [u] dat total )
        : *u dpp ( vec_data [u] dat )
        : ~ i j 0
        ~ < j total { = . dpp j # u & 255 * j 11 = j + j 1 }
        : ( Vec u ) o1 ( chacha20_xor_range key counter non dat doff n )
        : ( Vec u ) o2 ( _chacha20_xor_range_scalar key counter non dat doff n )
        : *u p1 ( vec_data [u] o1 )
        : *u p2 ( vec_data [u] o2 )
        = j 0
        ~ < j n {
            ? != & 255 # i . p1 j & 255 # i . p2 j {
                ? < g_bad 6 {
                    ( nurl_print `MISMATCH ctr=` ) ( nurl_print_int counter )
                    ( nurl_print ` doff=` ) ( nurl_print_int doff )
                    ( nurl_print ` n=` ) ( nurl_print_int n )
                    ( nurl_print ` at=` ) ( nurl_println_int j )
                    ( nurl_println `` )
                } {}
                = g_bad + g_bad 1
            } {}
            = j + j 1
        }
        ( vec_free [u] o1 ) ( vec_free [u] o2 ) ( vec_free [u] dat )
        = n + n 1
    }
    ( vec_free [u] key ) ( vec_free [u] non )
}

@ main → i {
    ( sweep 0 0 )
    ( sweep 1 0 )
    // A counter close to the 32-bit wrap, and a data offset that leaves
    // the input pointer unaligned to the vector width.
    ( sweep 4294967294 3 )
    ? == g_bad 0 { ( nurl_println `chacha20: vector kernel matches the scalar reference` ) }
    { ( nurl_print `chacha20: ` ) ( nurl_print_int g_bad ) ( nurl_println ` differing bytes` ) }
    ^ 0
}
