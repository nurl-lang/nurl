// defer_body_own_locals.nu — a defer body's own bindings are a scope of
// their own (agora #405): dropped at the body's end, inside the defer
// chain, never at a `^` in the main flow. Registered in the function's
// scope, a defer-local Vec was dropped at every return before the body
// had run (its slot held nothing: SEGV), and never after it had (a leak).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// The body's Vec, then a binding of the same name after the defer.
@ reuse i k → i {
    ; { : ( Vec i ) g ( vec_new [i] ) ( vec_push [i] g 7 ) ( nurl_println_int ( vec_len [i] g ) ) }
    : ( Vec i ) g ( vec_new [i] )
    ( vec_push [i] g 1 )
    ( vec_push [i] g 2 )
    ( nurl_println_int ( vec_len [i] g ) )
    ^ k
}

// Two defers, each with a Vec of its own (LIFO).
@ two i k → i {
    ; { : ( Vec i ) a ( vec_new [i] ) ( vec_push [i] a 7 ) ( nurl_println_int ( vec_len [i] a ) ) }
    ; { : ( Vec i ) b ( vec_new [i] ) ( vec_push [i] b 8 ) ( vec_push [i] b 9 ) ( nurl_println_int ( vec_len [i] b ) ) }
    ^ k
}

// The Vec only, and two ways out.
@ early i k → i {
    ; { : ( Vec i ) g ( vec_new [i] ) }
    ? == k 0 { ^ 1 } {}
    ^ k
}

// A String and a Vec of Strings of the body's own, and a loop's defer
// (run once, at the exit) with a String of its own.
@ owned i k → i {
    ; {
        : String s ( string_from `a defer-local string, long enough for the heap` )
        : ( Vec String ) vs ( vec_new [String] )
        ( vec_push [String] vs ( string_from `a defer-local element, long enough for the heap` ) )
        ( nurl_println ( string_data s ) )
        ( nurl_println_int ( vec_len [String] vs ) )
    }
    : ~ i j k
    ~ < j 3 {
        ; { : String t ( string_from `a loop defer's own string, long enough here` ) ( nurl_println ( string_data t ) ) }
        = j + j 1
    }
    ^ j
}

@ main → i {
    ( nurl_println_int ( reuse 2 ) )
    ( nurl_println_int ( two 3 ) )
    ( nurl_println_int ( early 2 ) )
    ( nurl_println_int ( early 0 ) )
    ( nurl_println_int ( owned 0 ) )
    ^ 0
}
