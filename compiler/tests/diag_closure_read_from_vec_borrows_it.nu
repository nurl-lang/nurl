// diag_closure_read_from_vec_borrows_it.nu — a closure read out of a Vec
// (`( vec_at [( @ u64 u64 )] fs 0 )`) is lent, not copied (spec §8.4,
// Agora #552): the binding borrows fs, so running it after fs is cleared,
// freed or given a new element is refused. (Before #552 every read
// cloned the env, so these ran on a copy; the read now allocates nothing.)
// fs is a local Vec the function owns by name: a Vec reached any other way
// is still copied at the read.

$ `stdlib/core/vec.nu`

@ mk u64 k → ( @ u64 u64 ) { ^ \ u64 x → u64 { ^ + x k } }

@ after_clear ( Vec u64 ) cap → u64 {
    : ( Vec ( @ u64 u64 ) ) fs ( vec_new [( @ u64 u64 )] )
    ( vec_push [( @ u64 u64 )] fs ( mk ( vec_at [u64] cap 0 ) ) )
    : ( @ u64 u64 ) f ( vec_at [( @ u64 u64 )] fs 0 )
    ( vec_clear [( @ u64 u64 )] fs )
    ^ ( f 1 )
}

@ after_free ( Vec u64 ) cap → u64 {
    : ( Vec ( @ u64 u64 ) ) fs ( vec_new [( @ u64 u64 )] )
    ( vec_push [( @ u64 u64 )] fs ( mk ( vec_at [u64] cap 0 ) ) )
    : ( @ u64 u64 ) f ( vec_at [( @ u64 u64 )] fs 0 )
    ( vec_free [( @ u64 u64 )] fs )
    ^ ( f 1 )
}

@ after_set ( Vec u64 ) cap → u64 {
    : ( Vec ( @ u64 u64 ) ) fs ( vec_new [( @ u64 u64 )] )
    ( vec_push [( @ u64 u64 )] fs ( mk ( vec_at [u64] cap 0 ) ) )
    : ( @ u64 u64 ) f ( vec_at [( @ u64 u64 )] fs 0 )
    ( vec_set [( @ u64 u64 )] fs 0 \ u64 y → u64 { ^ y } )
    ^ ( f 1 )
}

@ main → i {
    : ( Vec u64 ) cap ( vec_new [u64] )
    ( vec_push [u64] cap 7 )
    ^ # i + + ( after_clear cap ) ( after_free cap ) ( after_set cap )
}
