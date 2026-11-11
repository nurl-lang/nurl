// diag_lit_lent_beside_owned_nocopy.nu — agora #635: a struct literal
// handed back with a field of its own (a fresh String) beside a field it
// only borrows (a parameter's field). A borrowed field that can be copied
// is copied; one that cannot leaves no sound answer — lent whole, the
// fresh field is released by no one; owned whole, the borrowed one twice.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

: SE { String name Bomb b }

@ f Holder h → SE { ^ @ SE { ( string_from `a fresh name long enough for the heap` ) . h inner } }

@ main → i {
    : Holder h @ Holder { ( string_from `nm` ) ( bomb `inner` 0 ) }
    : SE r ( f h )
    ( see `main` . r b )
    ^ 0
}
