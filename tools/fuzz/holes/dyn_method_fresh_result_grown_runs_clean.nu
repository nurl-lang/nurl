// dyn_method_fresh_result_grown_runs_clean: an impl handing back `( string_from … )`, the result grown, a view of the caller's `. app name` read after
// Kept: a dyn method whose impls hand back a fresh value lends nothing; growing the result leaves the argument's views (agora #800).
// main 006aa3e8: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #800: a dyn method's fresh result grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name ( Vec i ) ns }

% Namer [T] { @ name_of T self i k App a → String }

: P { i t }

% Namer P { @ name_of P self i k App a → String { ^ ( string_from `fresh name long enough for heap` ) } }

@ ext App a → v {
    : P p @ P { 1 }
    : %Namer d ( dyn Namer p )
    : String r ( name_of d ( vec_at [i] . a ns 0 ) a )
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
