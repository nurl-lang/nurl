// agora #687: a `dyn` let as the first statement of a closure body, after
// a call in the enclosing function that hands back an owned value. The
// let took the box's drop flag from that call's ownership bit — a
// register of the enclosing function, undefined in the closure's own
// (clang refused the IR). A `( dyn … )` box is always fresh and owned,
// and a closure body starts with no last call of its own.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Taker [T] { @ take T self i k → i }

: G { i n }

% Taker G { @ take G g i k → i { ^ + k . g n } }

: Bx { ( Vec i ) v i n }

% Sizer [T] { @ size T self Bx x i k → i }

% Sizer G { @ size G g Bx x i k → i { ^ + + k . g n ( vec_len [i] . x v ) } }

@ main → i {
    : String s ( string_from `hello` )
    : ( @ i i ) work \ i k → i {
        : G g @ G { 1 }
        : %Taker d ( dyn Taker g )
        ^ ( take d k )
    }
    ( nurl_println ( nurl_str_int ( work 3 ) ) )
    // The same with an inline literal and a capture read after it.
    : ( @ i i ) work2 \ i k → i {
        : %Taker d ( dyn Taker @ G { 2 } )
        ^ + ( take d k ) ( string_len s )
    }
    ( nurl_println ( nurl_str_int ( work2 3 ) ) )
    // A captured struct that owns a Vec, handed to the method.
    : Bx a @ Bx { ( vec_new [i] ) 1 }
    ( vec_push [i] . a v 7 )
    : ( @ i i ) work3 \ i k → i {
        : G g @ G { 1 }
        : %Sizer d ( dyn Sizer g )
        ^ ( size d a k )
    }
    ( nurl_println ( nurl_str_int ( work3 3 ) ) )
    ^ 0
}
