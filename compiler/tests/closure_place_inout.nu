// closure_place_inout.nu — a closure binding reached through a pointer is
// a place that owns its env, as a struct field is (docs/MEMORY.md §7.4,
// h297): an `inout` parameter, or a binding a closure captured by pointer.
//
// 1. replaced in a callee; 2. a callee storing a closure it borrows (a
// copy goes in); 3. a binding that only borrows its closure, handed over
// (it is copied first); 4. forwarded to another inout callee; 5. a closure
// assigning a captured closure, per element, in a loop; 6. the same two
// closures deep; 7. the caller replacing it again afterwards; 8. a panic
// right after the callee replaced it (the replacement stays, nothing is
// freed twice); 9. a captured closure handed over by address from inside
// a closure.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: Holder { ( @ i i ) cb }

@ swap inout ( @ i i ) g i k → v { = g \ i x → i { ^ * x k } }

@ copy_in inout ( @ i i ) g ( @ i i ) src → v { = g src }

@ forward inout ( @ i i ) g → v { ( swap g 4 ) }

@ get_cb Holder h → ( @ i i ) { ^ . h cb }

@ call_held Holder h i x → i { : ( @ i i ) c . h cb ^ ( c x ) }

@ boom inout ( @ i i ) g → v { ( swap g 9 ) ( panic `boom` ) }

@ main → i {
    : i base 7
    // 1. replaced in a callee
    : ~ ( @ i i ) f \ i x → i { ^ + x base }
    ( swap f 3 )
    ( nurl_println ( nurl_str_cat `1 ` ( nurl_str_int ( f 5 ) ) ) )
    // 2. a borrowed closure stored by a callee
    : String tag ( string_from `tag` )
    : ( @ i i ) other \ i x → i { ^ + x ( string_len tag ) }
    ( copy_in f other )
    ( nurl_println ( nurl_str_cat `2 ` ( nurl_str_int ( f 5 ) ) ) )
    ( nurl_println ( nurl_str_cat `2b ` ( nurl_str_int ( other 5 ) ) ) )
    // 3. a binding that only borrows its closure, handed over
    : Holder h @ Holder { \ i x → i { ^ - x 1 } }
    : ~ ( @ i i ) b ( get_cb h )
    ( swap b 6 )
    ( nurl_println ( nurl_str_cat `3 ` ( nurl_str_int ( b 5 ) ) ) )
    ( nurl_println ( nurl_str_cat `3b ` ( nurl_str_int ( call_held h 5 ) ) ) )
    // 4. forwarded
    ( forward f )
    ( nurl_println ( nurl_str_cat `4 ` ( nurl_str_int ( f 5 ) ) ) )
    // 5. a closure assigning a captured closure, nested, in a loop
    : ~ ( @ i i ) g \ i x → i { ^ x }
    : ( Vec i ) ks ( vec_new [i] )
    ( vec_push [i] ks 2 ) ( vec_push [i] ks 3 )
    : ~ i k 0
    ~ < k 3 {
        ( vec_each [i] ks \ i m → v {
            : String s ( string_from `abc` )
            = g \ i x → i { ^ + * x m ( string_len s ) }
        } )
        = k + k 1
    }
    ( nurl_println ( nurl_str_cat `5 ` ( nurl_str_int ( g 5 ) ) ) )
    // 6. nested closure assigning the outer binding through two levels
    : ~ ( @ i i ) n \ i x → i { ^ x }
    ( vec_each [i] ks \ i m → v {
        ( vec_each [i] ks \ i q → v { = n \ i x → i { ^ + x + m q } } )
    } )
    ( nurl_println ( nurl_str_cat `6 ` ( nurl_str_int ( n 5 ) ) ) )
    // 7. the caller replaces it again after the closure ran
    = g \ i x → i { ^ - x base }
    ( nurl_println ( nurl_str_cat `7 ` ( nurl_str_int ( g 5 ) ) ) )
    // 8. a panic after the callee replaced it
    : ~ ( @ i i ) p \ i x → i { ^ + x base }
    : !v PanicInfo r ( recover \ → v { ( boom p ) } )
    ?? r { T _ → {} F e → { ( panic_info_free e ) } }
    ( nurl_println ( nurl_str_cat `8 ` ( nurl_str_int ( p 5 ) ) ) )
    // 9. a body place handed over by address
    : ~ ( @ i i ) w \ i x → i { ^ x }
    ( vec_each [i] ks \ i m → v { ( swap w m ) } )
    ( nurl_println ( nurl_str_cat `9 ` ( nurl_str_int ( w 5 ) ) ) )
    ^ 0
}
