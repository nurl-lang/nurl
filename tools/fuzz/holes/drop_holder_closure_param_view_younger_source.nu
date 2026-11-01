// drop_holder_closure_param_view_younger_source: agora #312 — a `% Drop` holder given, by a closure, its parameter's view of a younger String: the String drops first and the holder's destructor reads it.
// Closed: a closure cannot give one of its captures, or its own `inout` parameter, a value that may hold a view — a whole assignment, a field store, a push or keep the callee really stores — since a closure's type does not say what running it stores, so nothing where it runs follows the view; A2's CapsOK and Implements (__clo_cap_marks, bck_clo_cap_view_diag, agora #312).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #312: a closure giving a Drop holder capture its parameter's view of a younger String
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { ( string_data a ) }
    : ( @ v s ) setw \ s p → v { = w @ W { p } }
    : String b ( string_from `a younger string, declared after the holder` )
    ( setw ( string_data b ) )
    ^ 0
}
