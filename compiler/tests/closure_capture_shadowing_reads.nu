// closure_capture_shadowing_reads.nu — where a closure body reads the
// outer binding a name of its own shadows elsewhere, the outer one is still
// captured (agora #125, the other side of closure_capture_shadowing.nu): a
// `:` binding's value reads the outer `w` (the name is bound only once the
// value ends), an arm reads it after the arm that bound `w` is over, and a
// nested closure reads it outside its own `w` parameter's body.

$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 7 )
    ( vec_push [i] w 8 )
    : ( @ i ) g \ → i {
        : i w + ( vec_len [i] w ) 10
        ^ w
    }
    ( nurl_println_int ( g ) )
    : ?i o @ ?i { F }
    : ( @ i ) h \ → i {
        ^ ?? o {
            T w → w
            F → ( vec_len [i] w )
        }
    }
    ( nurl_println_int ( h ) )
    : ( @ i ) k \ → i {
        : ( @ i i ) f \ i w → i { ^ + w 1 }
        ^ + ( f 1 ) ( vec_len [i] w )
    }
    ( nurl_println_int ( k ) )
    ^ 0
}
