// field_of_a_field_of_a_call_result_grown_inline_past_a_slice_of_it: agora #349 — `( vec_reserve . . ( vec_at os 0 ) inner data n )` with a slice of that field kept
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: a field of a field of a call result grown inline past a slice of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: I { ( Vec u ) data }
: O { I inner }

@ main → i {
    : ( Vec O ) os ( vec_new [O] )
    ( vec_push [O] os @ O { @ I { ( vec_new [u] ) } } )
    ( vec_push [u] . . ( vec_at [O] os 0 ) inner data 7 )
    : ( Slice u ) sl ( slice_from_vec [u] . . ( vec_at [O] os 0 ) inner data )
    ( vec_reserve [u] . . ( vec_at [O] os 0 ) inner data 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
