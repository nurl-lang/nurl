// drop_element_from_a_lending_call_changed_by_a_helper_is_refused: the same through `@ vg ( Vec R ) rs → v { ( rg ( vec_at [R] rs 0 ) ) }`, `( vg rs )`
// Closed: agora #692 (the helper's summary has the edge now).
// main f9102b40: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #692: a helper changing a % Drop element it got from a lending call changes its container
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
    ( vg rs )
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
