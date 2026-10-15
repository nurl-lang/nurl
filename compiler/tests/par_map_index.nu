// par_map_index (stdlib/std/par.nu): f k for every index on several threads,
// the results by index; the closure shares what it reads through an Arc.
$ `stdlib/core/io.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/par.nu`

@ main → i {
    : ( Arc ( Vec f ) ) data ( arc_new [( Vec f )] ( vec_zeroed [f] 1000 ) )
    : ( Vec f ) r ( par_map_index [f] 37 4 \ i k → f {
        : ( Vec f ) d ( arc_get [( Vec f )] data )
        : ~ f s 0.0
        : ~ i j 0
        ~ < j ( vec_len [f] d ) { = s + s # f + j k = j + j 1 }
        ^ s
    } )
    : ~ f t 0.0
    : ~ i k 0
    ~ < k ( vec_len [f] r ) { = t + t ( vec_at [f] r k ) = k + k 1 }
    ( nurl_println_int ( vec_len [f] r ) ) ( nurl_println ( nurl_str_float t ) )
    ^ 0
}
