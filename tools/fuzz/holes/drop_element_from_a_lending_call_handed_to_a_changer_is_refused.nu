// drop_element_from_a_lending_call_handed_to_a_changer_is_refused: `( rg ( vec_at [R] rs 0 ) )`, R a struct with its own `% Drop` and a Vec field `rg` grows, a Slice of that Vec read after
// Closed: an argument that is a call's result is traced to what lent it when its type holds storage a callee can change in place, a `% Drop` struct with a Vec field included (__arg_holds_changeable, agora #692).
// main f9102b40: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #692: a % Drop element from a lending call handed to a changer ends the views of its buffer
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
