// closure_field_store_to_a_single_field_capture_vec: agora #356 — a closure gives a captured single-field `: ~` struct's Vec field a new Vec and pushes onto it: the struct was captured by value, so both landed in the env's copy, the binding still held its old Vec and the new one leaked.
// Closed: the root of a field-path store target counts as assigned, so the closure takes the binding by pointer (simple_capture_analysis, MEMORY.md §2.3, agora #356).
// main: accepted; printed 0 and LSan reported 56 bytes leaked.
// map: §2.3 | A2 | runs-clean | - | agora #356: a closure replacing a Vec field of a captured single-field struct
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`

: B { ( Vec i ) items }

@ main → i {
    : ~ B b @ B { ( vec_new [i] ) }
    : ( @ v ) f \ → v {
        = . b items ( vec_new [i] )
        ( vec_push [i] . b items 5 )
    }
    ( f )
    ( nurl_println_int ( vec_len [i] . b items ) )
    ^ 0
}
