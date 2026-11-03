// closure_clears_a_local_joined_out_of_its_capture: a closure clears a local given a join of two elements of its capture, while the caller still reads a String inside that element.
// Closed: a closure body's local read out of a capture through a join, a ?? payload or a generic identity is that capture, as one read out of it directly is — its sources are the bindings the value's source expression names (agora #449).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #449: a closure clears a local given a join of two elements of its capture, while the caller still reads a String inside that element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: HS { ( Vec String ) xs }

@ clr ( Vec String ) x → v { ( vec_clear [String] x ) }

@ idv [T] T x → T { ^ x }

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] vv 0 ) ( string_from `an element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 )
    : ( @ v ) wipe \ → v { : ( Vec String ) e ? > ( vec_len [( Vec String )] vv ) 0 ( vec_at [( Vec String )] vv 0 ) ( vec_at [( Vec String )] vv 0 ) ( vec_clear [String] e ) }
    ( wipe )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
