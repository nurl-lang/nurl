// slice_at past either end panics, naming the index and the length; the
// panic is recoverable.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    : !v PanicInfo lo ( recover \ → v { ( nurl_println_int ( slice_at [i] s -1 ) ) } )
    ?? lo { T _ → { ( nurl_println `no panic` ) } F p → { ( nurl_println ( string_data . p msg ) ) } }
    : !v PanicInfo hi ( recover \ → v { ( slice_put [i] s 1 9 ) } )
    ?? hi { T _ → { ( nurl_println `no panic` ) } F p → { ( nurl_println ( string_data . p msg ) ) } }
    ^ 0
}
