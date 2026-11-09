// value_block_ending_in_a_local_lend_cleared_past_a_view_inside: agora #349 — `( vec_clear { : t ( vec_at vs 0 ) t } )` while a view of an inner String is kept
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: a value block ending in a local lend cleared past a view inside
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vs ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vs ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] vs 0 ) ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] vs 0 ) 0 ) )
    ( vec_clear [String] { : ( Vec String ) t ( vec_at [( Vec String )] vs 0 ) t } )
    ( nurl_println d )
    ^ 0
}
