// diag_thread_arc_payload_through_call.nu — a detached closure that mutates
// an Arc's payload without naming a view of it (h212).
//
// diag_thread_arc_shared_mutation.nu covers `: v ( arc_get a )` followed by
// a container mutator on `v`. The same race was accepted when the payload
// reached the mutation any other way:
//
//   ( vec_push ( arc_get a ) x )            — the view written in place
//   ( vec_push . view field x )             — a field of a view
//   ( grow view )                           — a helper that mutates it
//   ( string_push_char view c )             — a String (or a map) mutator
//
// The last writes through raw pointers, so its mutation summary is known
// only once every body is compiled: the verdict is reached then, at the
// call that hands the payload over. Measured before the fix, a String
// pushed from two threads: lost updates in every run and `realloc():
// invalid old size`.

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Arc String ) a ( arc_new [String] ( string_from `x` ) )
    : ( Arc String ) b ( arc_clone [String] a )
    : !Thread ThreadErr t ( thread_spawn \ → v {
        : ~ i k 0
        ~ < k 1000 { ( string_push_char ( arc_get [String] b ) 65 ) = k + k 1 }
    } )
    ( string_push_char ( arc_get [String] a ) 66 )
    ^ 0
}
