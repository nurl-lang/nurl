// What closures may hand back (h219, h220): a value the body makes, even
// one that cannot be copied; a raw string it only lent, which the caller
// gets as its own copy; a view of an argument, read while the argument is
// unchanged. A function still lends its parameter's field that cannot be
// copied.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

@ held Hold h → Res { . h r }

@ main → i {
    : ( @ Res ) mk \ → Res { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 3 ) @ Res { v } }
    : Res a ( mk )
    : Res b ( mk )
    : String s ( string_from `abc` )
    : ( @ s ) view \ → s { ( string_data s ) }
    : s p ( view )
    ( string_push_str s `defghijklmnopqrstuvwxyz` )
    ( nurl_println p )
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 7 )
    : ( @ ( Slice i ) ( Vec i ) ) sv \ ( Vec i ) x → ( Slice i ) { ( slice_from_vec [i] x ) }
    : ( Slice i ) sl ( sv w )
    ( nurl_println_int ( slice_len [i] sl ) )
    : ( Vec i ) hv ( vec_new [i] )
    ( vec_push [i] hv 4 )
    ( vec_push [i] hv 5 )
    : Hold h @ Hold { @ Res { hv } 1 }
    ( nurl_println_int ( vec_len [i] . ( held h ) buf ) )
    ( nurl_println_int + ( vec_len [i] . a buf ) ( vec_len [i] . b buf ) )
    ^ 0
}
