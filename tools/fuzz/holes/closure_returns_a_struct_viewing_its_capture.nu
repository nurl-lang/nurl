// closure_returns_a_struct_viewing_its_capture: a closure hands back a struct holding a view of its captured String beside an owned field, pushed into an outer Vec past the String.
// Closed: a closure call's result that can hold views has the closure's captures among its sources, beside its arguments (__clo_call_sx), so a value holding a view of a capture is tied to it (agora #369).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #369: a closure hands back a struct holding a view of its captured String beside an owned field, pushed into an outer Vec past the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: T2 { s v String o }

@ main → i {
    : ~ ( Vec T2 ) toks ( vec_new [T2] )
    {
        : String line ( string_from `the inner string, freed at the end of its block` )
        : ( @ T2 ) mk \ → T2 { ^ @ T2 { ( string_data line ) ( string_from `owned` ) } }
        ( vec_push [T2] toks ( mk ) )
    }
    ( nurl_println . ( vec_at [T2] toks 0 ) v )
    ( vec_free [T2] toks )
    ^ 0
}
