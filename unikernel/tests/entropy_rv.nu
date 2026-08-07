// unikernel/tests/entropy_rv.nu — is the entropy real?
//
// Two draws, and the two ways a fake source looks plausible: all
// zeroes (a device that answered without writing), and two draws that
// match (a source that is a constant, or a buffer read twice). The
// gate also runs this WITHOUT a virtio-rng device, where the machine
// must refuse by name instead of returning something.
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

& `c` @ nurl_rand_fill *u buf i n → i

@ main → i {
    : ( Vec u ) b ( vec_with_cap [u] 32 )
    ( vec_set_len [u] b 32 )
    : i r ( nurl_rand_fill ( vec_data [u] b ) 32 )
    ( nurl_print `rand_fill=` ) ( nurl_print_int r ) ( nurl_print `\n` )
    // Two draws must differ, and neither may be all zeroes — the two
    // ways a fake entropy source looks plausible.
    : ~ i zeros 0
    : ~ i k 0
    ~ < k 32 { ? == # i . ( vec_data [u] b ) k 0 { = zeros + zeros 1 } {} = k + k 1 }
    ( nurl_print `zeros=` ) ( nurl_print_int zeros ) ( nurl_print `\n` )
    : ( Vec u ) c ( vec_with_cap [u] 32 )
    ( vec_set_len [u] c 32 )
    : i r2 ( nurl_rand_fill ( vec_data [u] c ) 32 )
    : ~ i same 0
    : ~ i j 0
    ~ < j 32 {
        ? == # i . ( vec_data [u] b ) j # i . ( vec_data [u] c ) j { = same + same 1 } {}
        = j + j 1
    }
    ( nurl_print `same_bytes=` ) ( nurl_print_int same ) ( nurl_print `\n` )
    ( vec_free [u] b ) ( vec_free [u] c )
    ^ 0
}
