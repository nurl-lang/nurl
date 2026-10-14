// slice_window: the `n` elements from `from`, checked once; a loop to
// `n` over the window indexes it with no per-element failure. Past the
// slice it panics, naming the end it wanted and the length.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k 10 { ( vec_push [i] v * k k ) = k + k 1 }
    : ( Slice i ) all ( slice_from_vec [i] v )
    : ( Slice i ) w ( slice_window [i] all 3 4 )
    : ~ i s 0
    = k 0
    ~ < k ( slice_len [i] w ) { = s + s ( slice_at [i] w k ) = k + k 1 }
    ( nurl_println_int s )  // 9 + 16 + 25 + 36
    ( slice_put [i] w 0 100 )
    ( nurl_println_int ( vec_at [i] v 3 ) )
    ( nurl_println_int ( slice_len [i] ( slice_window [i] all 10 0 ) ) )
    : !v PanicInfo past ( recover \ → v { ( nurl_println_int ( slice_len [i] ( slice_window [i] all 8 3 ) ) ) } )
    ?? past { T _ → { ( nurl_println `no panic` ) } F p → { ( nurl_println ( string_data . p msg ) ) } }
    : !v PanicInfo neg ( recover \ → v { ( nurl_println_int ( slice_len [i] ( slice_window [i] all -1 2 ) ) ) } )
    ?? neg { T _ → { ( nurl_println `no panic` ) } F p → { ( nurl_println ( string_data . p msg ) ) } }
    ^ 0
}
