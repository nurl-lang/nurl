// A generic is stored at its declaration and monomorphised after the
// whole program is parsed, long after the `simd` prefix was read and
// cleared — so its instantiations would come out unmarked. Rather than
// accept a prefix that quietly does nothing, nurlc rejects it.
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`

simd @ count [T] ( Vec T ) v → i { ^ ( vec_len [T] v ) }

@ main → v {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    ( nurl_print ( nurl_str_int ( count [i] xs ) ) )
    ( vec_free [i] xs )
}
