// return_of_a_nested_generic_lending_call_of_a_field_runs_clean: `^ ( gb [String] ( id0 . p name ) )` — a generic lender over a lender of a struct parameter's field; the caller reads the result and the struct.
// Agora #777: each link of the chain lends its argument, so the result lends `p`; before, the caller released the struct's field under the result.
// map: §2.10 | A2 | runs-clean | - | agora #777: a generic link and a field root in a nested lend chain
$ `stdlib/core/string.nu`

: O { String name i n }

@ id0 String x → String { ^ x }

@ gb [A] A x → A { ^ x }

@ f O p → String { ^ ( gb [String] ( id0 . p name ) ) }

@ main → i {
    : O o @ O { ( string_from `the struct's name, long enough for the heap` ) 1 }
    : String r ( f o )
    ( nurl_println ( string_data r ) )
    ( nurl_println ( string_data . o name ) )
    ^ - . o n 1
}
