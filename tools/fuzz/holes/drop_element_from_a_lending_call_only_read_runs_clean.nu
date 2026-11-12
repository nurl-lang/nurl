// drop_element_from_a_lending_call_only_read_runs_clean: `( peek ( vec_at [R] rs 0 ) )`, R with its own `% Drop`, `peek` only reading the element, a Slice of its Vec read after
// Guard for agora #692's fix: tracing the argument ends views only where the callee may change it.
// main f9102b40: accepted, clean.
// map: §2.10 | A2 | runs-clean | - | agora #692 guard: a % Drop element from a lending call that is only read keeps the views of its buffer
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
    : i k ( peek ( vec_at [R] rs 0 ) )
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
