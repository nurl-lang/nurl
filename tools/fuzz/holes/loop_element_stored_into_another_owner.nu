// loop_element_stored_into_another_owner: agora #635 — `~ x v { ( vec_push [D] out x ) }` and `~ x v { : W w @ W { x 1 } … }`: a loop's element that cannot be copied stored into another owner while its Vec keeps it.
// Closed: a view (a `~` loop's element, a binding of a field read or of a binding that owns nothing) of a type that cannot be copied is lent wherever it is stored (mem_lent_cond), so the store is refused as a store of a borrowed value is.
// main: accepted; AddressSanitizer reported heap-use-after-free (the element dropped by both owners).
// map: §7.6 | A2 | rejected | - | agora #635: `~ x v { ( vec_push [D] out x ) }` and `~ x v { : W w @ W { x 1 } … }`: a loop's element that cannot be copied stored into another owner while its Vec keeps it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ cp ( Vec Bomb ) v inout ( Vec Bomb ) out → v { ~ x v { ( vec_push [Bomb] out x ) } }

@ main → i {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `e0` 0 ) )
    : ~ ( Vec Bomb ) out ( vec_new [Bomb] )
    ( cp v out )
    ( nurl_println_int ( vec_len [Bomb] out ) )
    ^ 0
}
