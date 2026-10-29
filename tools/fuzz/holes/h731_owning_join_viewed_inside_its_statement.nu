// H731: a `??` join with an arm that owns its value (a fresh String) handed
// to a call whose result may view it — `( string_data ?? ( vec_get v k ) {
// T x → x F _ → ( string_from … ) } )` — used inside a call that consumes
// the view: the joined value was dropped by no one on the owning path.
// Closed: such a join is a temporary of the call, deferred as a call's is
// (`__deferred_temps__`), and dropped after the consuming call by the
// join's ownership bit (agora #181).
// v0.80.0: HOLE (detected memory leaks).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a string long enough to own a heap buffer here` ) )
    : ~ i k 0
    ~ < k 4 {
        ( nurl_println ( string_data ?? ( vec_get [String] v k ) { T x → x F _ → ( string_from `a fresh string long enough to own a heap buffer` ) } ) )
        = k + k 1
    }
    ^ 0
}
