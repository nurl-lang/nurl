// H732: as h731, the view bound and kept past its statement: nothing could
// release the join's value then without leaving the view dangling.
// Closed: rejected as a view of a call's temporary kept past its statement
// is — bind the join first (agora #181).
// v0.80.0: HOLE (detected memory leaks).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a string long enough to own a heap buffer here` ) )
    : ~ i k 0
    ~ < k 4 {
        : s w ( string_data ?? ( vec_get [String] v k ) { T x → x F _ → ( string_from `a fresh string long enough to own a heap buffer` ) } )
        ( nurl_println w )
        = k + k 1
    }
    ^ 0
}
