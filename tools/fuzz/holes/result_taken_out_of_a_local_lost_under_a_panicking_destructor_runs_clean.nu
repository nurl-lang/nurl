// result_taken_out_of_a_local_lost_under_a_panicking_destructor_runs_clean: `^ . h name` of a local struct, and `^ s` of a local enum's payload, while another local's destructor panics on the way out; the panic is recovered.
// Agora #814 / #677 D: the taken value lived in a register only while the locals were dropped, and the unwind lost it (a leak); it is journaled now (ret_field_copy → mem_ret_guard_push).
// map: §7.6 | A2 | runs-clean | - | agora #814: a result taken out of a local survives a panicking destructor
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
        ? == . b boom 1 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {}
    }
}

: Holder { String name i n }
: | E { EA String EB i }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

@ field_ret → String {
    : Holder h @ Holder { ( string_from `a holder name, long enough for heap` ) 1 }
    : Bomb loc ( bomb `field.local` 1 )
    ^ . h name
}

@ payload_ret → String {
    : E e @ E { EA ( string_from `an enum payload, long enough for heap` ) }
    : Bomb loc ( bomb `payload.local` 1 )
    ?? e { EA s → { ^ s } EB j → {} }
    ^ ( string_from `none` )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `field` \ → v { : String r ( field_ret ) ( nurl_println `not reached` ) } )
    ( run `payload` \ → v { : String r ( payload_ret ) ( nurl_println `not reached` ) } )
    ^ 0
}
