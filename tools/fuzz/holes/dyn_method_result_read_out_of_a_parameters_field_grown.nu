// dyn_method_result_read_out_of_a_parameters_field_grown: `: String r ( name_of d 0 a )`, the impl handing back `. a name`, then `( string_push_str r … )`, a view of the caller's `. app name` read after
// Closed: a `dyn` method call's virtual callee lends what any impl lends — its lend summaries (the union of the impls', __dyn_virtual_round) are made before the edges a source expression conditions are kept or dropped (resolve_cond_edges): a value it hands back out of an argument is read out of that argument (agora #800 item 2).
// main 006aa3e8: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #800: a dyn method result read out of a parameter's field, grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name ( Vec i ) ns }

% Namer [T] { @ name_of T self i k App a → String }

: P { i t }

% Namer P { @ name_of P self i k App a → String { ^ . a name } }

@ ext App a → v {
    : P p @ P { 1 }
    : %Namer d ( dyn Namer p )
    : String r ( name_of d 0 a )
    ( string_push_str r `, and a good deal more text so the buffer has to move somewhere else` )
}

@ main → i {
    : ( Vec i ) ns ( vec_new [i] )
    ( vec_push [i] ns 3 )
    : App app @ App { ( string_from `a name long enough to live on the heap` ) ns }
    : s view ( string_data . app name )
    ( ext app )
    ( nurl_eprintln view )
    ^ 0
}
