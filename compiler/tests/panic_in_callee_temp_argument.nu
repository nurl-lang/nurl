// panic_in_callee_temp_argument.nu — a call's result passed straight as an
// argument, when the callee panics (Agora #707).
//
// The temporary is the caller's to release once the call returns, so it is
// the caller's for the whole call: journaled for that window, a panic in the
// callee runs its destructor, once, and the unwind goes on to the `recover`.
// Before, only a handle temporary (a String, a Vec, a library handle) was
// journaled; a `% Drop` struct — or an option holding one — was in no
// journal entry, its destructor never ran and what it owned leaked. Bound
// first (`: Bomb p …  ( boom p 1 )`) it always was dropped.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i id }

% Drop Bomb {
    @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) }
}

@ bomb s tag i id → Bomb { ^ @ Bomb { ( string_from tag ) id } }

@ maybe s tag → ?Bomb { ^ @ ?Bomb { T ( bomb tag 3 ) } }

@ boom Bomb k i n → i { ? > n 0 { ( panic `boom` ) } {} ^ . k id }

@ boom3 i a Bomb k i n → i { ? > n 0 { ( panic `boom3` ) } {} ^ + a . k id }

@ boom_opt ? Bomb o i n → i { ? > n 0 { ( panic `boom_opt` ) } {} ^ 0 }

@ boom_str String s i n → i { ? > n 0 { ( panic `boom_str` ) } {} ^ ( string_len s ) }

@ temp → v { : i x ( boom ( bomb `temp` 2 ) 1 ) ( nurl_println `not reached` ) }

@ bound → v { : Bomb p ( bomb `bound` 2 ) : i x ( boom p 1 ) ( nurl_println `not reached` ) }

@ middle → v { : i x ( boom3 1 ( bomb `middle` 2 ) 1 ) ( nurl_println `not reached` ) }

@ option → v { : i x ( boom_opt ( maybe `option` ) 1 ) ( nurl_println `not reached` ) }

@ string → v { : i x ( boom_str ( string_from `a string temporary on the heap` ) 1 ) ( nurl_println `not reached` ) }

@ quiet → v { : i x ( boom ( bomb `quiet` 2 ) 0 ) ( nurl_println ( nurl_str_cat `quiet: ` ( nurl_str_int x ) ) ) }

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `temp` \ → v { ( temp ) } )
    ( run `bound` \ → v { ( bound ) } )
    ( run `middle` \ → v { ( middle ) } )
    ( run `option` \ → v { ( option ) } )
    ( run `string` \ → v { ( string ) } )
    ( run `quiet` \ → v { ( quiet ) } )
    ^ 0
}
