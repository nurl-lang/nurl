// defer_body_names_are_its_own.nu — a `;` defer body's names are its
// own (agora #636): a name it binds is named inside it only. Bound in the
// enclosing scope, the body's `: i a …` took the name `a` over for the rest
// of the function, and a later `a` read the body's storage — written only
// when the defer runs: uninitialised memory, a call through an unset
// closure, a String that was never made.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// An outer `a`, the body's `a`, the outer one returned.
@ scalar i n → i {
    : i a 5
    ; { : i a + n 7 ( nurl_println_int a ) }
    ^ a
}

// A closure of the body's under the name of an outer closure.
@ closure i n → i {
    : ( @ i i ) f \ i x → i { ^ + x 1 }
    ; { : ( @ i i ) f \ i x → i { ^ + x n } ( nurl_println_int ( f 100 ) ) }
    ^ ( f 0 )
}

// A String of the body's under the name of an outer String.
@ text i n → i {
    : String s ( string_from `the outer string, long enough for the heap` )
    ; { : String s ( string_from `the defer body's own string, also long enough` ) ( nurl_println_int ( string_len s ) ) }
    ^ + n ( string_len s )
}

// The body's own String and Vec, read by a defer registered inside it
// (which runs after the body), and released once, after the chain.
@ nested i n → i {
    : ~ i t n
    ; {
        : String s ( string_from `a defer-local string long enough for the heap` )
        : ~ ( Vec String ) vs ( vec_new [String] )
        ( vec_push [String] vs ( string_from `a defer-local element, long enough for the heap` ) )
        ; { ( nurl_println_int + ( string_len s ) ( vec_len [String] vs ) ) }
        : String late ( string_from `bound after the inner defer, long enough` )
        ( nurl_println_int ( string_len late ) )
    }
    = t + t 1
    ^ t
}

// The same name in two defer bodies and in the function, in a loop.
@ thrice i n → i {
    : ~ i k 0
    : ~ i x 1
    ~ < k n {
        ; { : i x * k 10 ( nurl_println_int x ) }
        = x + x k
        = k + k 1
    }
    ; { : i x 99 ( nurl_println_int x ) }
    ^ x
}

// What a body binds lives on after the body: an older defer reads a
// holder the newer body pointed at its own String, and a defer registered
// inside a body reads the body's slice.
: W { s v }

@ sum [i xs → i {
    : ~ i t 0
    ~ w xs { = t + t w }
    ^ t
}

@ lives i n → i {
    : ~ W w @ W { `start` }
    ; { ( nurl_println . w v ) }
    ; { : String b ( string_from `b: the newer defer's own string, long enough for the heap` ) = w @ W { ( string_data b ) } }
    ; { : [i xs [i | 1 2 3 n] ; { ( nurl_println_int ( sum xs ) ) } }
    ^ n
}

@ main → i {
    ( nurl_println_int ( lives 4 ) )
    ( nurl_println_int ( scalar 1 ) )
    ( nurl_println_int ( closure 3 ) )
    ( nurl_println_int ( text 2 ) )
    ( nurl_println_int ( nested 4 ) )
    ( nurl_println_int ( thrice 3 ) )
    ^ 0
}
