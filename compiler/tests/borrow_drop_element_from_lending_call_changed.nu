// borrow_drop_element_from_lending_call_changed.nu — `( rg ( vec_at [R] rs 0 ) )`,
// R a struct with its own `% Drop` and a Vec field that `rg` grows: the
// argument is traced to `rs`, so a Slice of the element's Vec taken before
// the call and read after it is refused, as for R without the Drop (Agora
// #692). The trace asked only whether the result was a handle, which a
// `% Drop` struct is not.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: R { ( Vec i ) v i n }

% Drop R { @ drop R r → v {} }

@ mkr → R { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ^ @ R { v 1 } }

@ rg R r → v { ( vec_reserve [i] . r v 4096 ) }

@ peek R r → i { ^ ( vec_len [i] . r v ) }

@ vg ( Vec R ) rs → v { ( rg ( vec_at [R] rs 0 ) ) }

@ main → i {
    : ( Vec R ) rs ( vec_new [R] )
    ( vec_push [R] rs ( mkr ) )
    : ( Slice i ) sl ( slice_from_vec [i] . ( vec_at [R] rs 0 ) v )
    ( rg ( vec_at [R] rs 0 ) )
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
