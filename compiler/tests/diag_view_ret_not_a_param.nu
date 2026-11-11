// diag_view_ret_not_a_param.nu — agora #635: a `~` loop's element (or a
// binding of a field read) of a type that cannot be copied is a view of
// the value where it is. Handed back out of a parameter the caller keeps
// it is lent; out of a local dropped on the way out there is nothing to
// lend and no copy to make, so the `^` is refused (it used to compile,
// and the caller dropped the element the Vec had already released).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ f → Bomb {
    : ~ ( Vec Bomb ) loc ( vec_new [Bomb] )
    ( vec_push [Bomb] loc ( bomb `l0` 0 ) )
    ~ x loc { ? == . x boom 0 { ^ x } {} }
    ^ ( bomb `none` 0 )
}

@ main → i {
    : Bomb r ( f )
    ( see `main` r )
    ^ 0
}
