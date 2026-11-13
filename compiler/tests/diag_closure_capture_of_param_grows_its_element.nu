// A closure that CAPTURES the enclosing function's parameter and grows
// its element changes what the caller passed: the caller's slice of it
// ends, as before #801 (whose change touches only a literal's own
// parameter of that name).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ top ( Vec ( Vec u ) ) vv → i {
    : ( @ v ( Vec ( Vec u ) ) ) g \ ( Vec ( Vec u ) ) other → v { ( vec_reserve [u] ( vec_at [( Vec u )] vv 0 ) 4096 ) }
    : ( Vec ( Vec u ) ) mine ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] mine ( vec_new [u] ) )
    ( g mine )
    ^ # i ( vec_len [( Vec u )] vv )
}

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    ( vec_push [( Vec u )] w inner )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( nurl_println_int ( top w ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
