// payload_view_of_a_param_element_returned_inside_an_if_then_cleared: agora #487 — `?? ( vec_get [String] p 0 ) { T e → { ^ ( string_data e ) } … }` inside an `if`: a view of p's element through a payload, and the caller clears p while holding it
// main: accepted; heap-use-after-free (a payload's lend reached the answer only when the `??` statement directly preceded the last `^`).
// map: §2.10 | A2 | rejected | - | agora #487: `?? ( vec_get [String] p 0 ) { T e → { ^ ( string_data e ) } … }` inside an `if`: a view of p's element through a payload, and the caller clears p while holding it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ first_str ( Vec String ) p → s {
    ? > ( vec_len [String] p ) 0 {
        ?? ( vec_get [String] p 0 ) { T e → { ^ ( string_data e ) } F → {} }
    } {}
    ^ ``
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer` ) )
    : s v ( first_str t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
