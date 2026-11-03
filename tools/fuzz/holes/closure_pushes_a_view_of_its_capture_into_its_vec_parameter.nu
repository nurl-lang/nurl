// closure_pushes_a_view_of_its_capture_into_its_vec_parameter: a closure pushes a view of a String it captured into its plain Vec parameter; the String ends before the caller reads the Vec.
// Closed: a closure's plain parameter that holds storage of its own (a `( Vec s )`) is a target for a view of one of the closure's captures, refused in the body as a capture or an `inout` parameter is (A2's Implements); a view of another parameter is the call's holder/source pair (agora #332, #403).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #332: a closure pushes a view of a String it captured into its plain Vec parameter; the String ends before the caller reads the Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec s ) hold ( vec_new [s] )
    {
        : String cap ( string_from `the first heap string, long enough to be on the heap for sure` )
        : ( @ v ( Vec s ) ) f \ ( Vec s ) h → v { ( vec_push [s] h ( string_data cap ) ) }
        ( f hold )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
