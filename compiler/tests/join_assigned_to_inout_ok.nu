// join_assigned_to_inout_ok.nu — a `?` / `??` assigned to an `inout`
// parameter or a binding a closure captured by reference (agora #183).
// Its value is the caller's: whatever the function binds moves out or is
// copied, a borrowed value is copied, and the caller's old value is
// dropped — also when an arm hands the binding back to itself.
// Runs clean under the sanitizers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ from_local inout String t b c → v {
    : String x ( mk )
    = t ? c x ( mk )
}

@ from_field inout String t b c → v {
    : P p @ P { ( mk ) 1 }
    = t ? c . p s ( mk )
}

@ from_param inout String t String p b c → v { = t ? c p ( mk ) }

@ from_self inout String t b c → v { = t ? c t ( mk ) }

@ from_option inout ? String o b c → v {
    : String x ( mk )
    = o ? c @ ?String { T x } @ ?String { F }
}

@ from_loop inout ( Vec String ) v i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec String ) w ( vec_new [String] )
        ( vec_push [String] w ( mk ) )
        = v ? > k 0 w ( vec_new [String] )
        = k + k 1
    }
}

@ main → i {
    : ~ String t ( mk )
    : String p ( mk )
    : ~ ? String o @ ?String { T ( mk ) }
    : ~ ( Vec String ) v ( vec_new [String] )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        ( from_local t > k 4 )
        ( from_field t > k 2 )
        ( from_param t p > k 6 )
        ( from_self t > k 5 )
        = acc + acc ( string_len t )
        ( from_option o > k 3 )
        = acc + acc ?? o { T s → ( string_len s ) F → 0 }
        ( from_loop v 3 )
        = acc + acc ( vec_len [String] v )
        = k + k 1
    }
    : ( @ v ) f \ → v {
        : String x ( mk )
        = t ? > acc 0 x ( mk )
    }
    ( f )
    ( nurl_println_int acc )
    ( nurl_println_int + ( string_len t ) ( string_len p ) )
    ^ 0
}
