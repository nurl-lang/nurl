// closure_handed_to_a_function_pushes_its_captures_view: the same closure literal handed straight to a function that calls it on the caller's Vec.
// Closed: a closure's plain parameter that holds storage of its own (a `( Vec s )`) is a target for a view of one of the closure's captures, refused in the body as a capture or an `inout` parameter is (A2's Implements); a view of another parameter is the call's holder/source pair (agora #332, #403).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #332: the same closure literal handed straight to a function that calls it on the caller's Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ hof ( @ v ( Vec s ) ) f ( Vec s ) h → v { ( f h ) }

@ main → i {
    : ( Vec s ) hold ( vec_new [s] )
    {
        : String cap ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( hof \ ( Vec s ) h → v { ( vec_push [s] h ( string_data cap ) ) } hold )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
