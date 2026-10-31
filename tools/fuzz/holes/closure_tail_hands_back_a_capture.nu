// closure_tail_hands_back_a_capture: a closure whose body falls off with a value it only lent — a call that lent (`( vec_at outer 0 )`), a capture handed back by name, a field of one, a binding that owns nothing — handed that value to its caller as its own: a call through a closure value owns its result, so the caller released what `outer` (or the env) still held. The same body written with `^` copied.
// Closed: the fall-off value is copied unless the body owns it — the callee's answer for a call, the drop flag for a binding the body keeps (a capture by pointer stays the enclosing frame's), always for a field read except out of a call that handed the whole over.
// main (before this PR): ASan heap-use-after-free.
// map: §2.11 | A2 | runs-clean | h217 | closure falls off with lent element of capture; caller treats it as owned
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) seed ( vec_new [i] )
    ( vec_push [i] seed 5 )
    : ( Vec ( Vec i ) ) outer ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] outer seed )
    : ( @ ( Vec i ) ) f \ → ( Vec i ) { ( vec_at [( Vec i )] outer 0 ) }
    ( vec_push [i] ( f ) 1 )
    ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] outer 0 ) ) )
    ^ 0
}
