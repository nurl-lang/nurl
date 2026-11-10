// inout_parameter_assigned_while_its_old_values_destructor_panics_leaves_the_caller_the_dropped_value: `= p new` through an `inout` parameter dropped the caller's old value before the store: when its destructor panicked under `recover`, the caller's binding still held the dropped value — the unwind (or the caller, outside the recover) dropped it again.
// Closed: an assignment takes the old value out first — the new value is stored, then the old one is dropped from a temporary (mem_replaced_drop / gen_assign) — so a panic in its destructor finds the target holding the new value, which is dropped once (agora #621).
// main (before this PR): AddressSanitizer heap-use-after-free in drop__Bomb.
// map: §7.6 | A2 | runs-clean | - | agora #621: an inout parameter assigned while the old value's destructor panics left the caller's binding holding the dropped value
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
        ? == . b boom 1 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {}
    }
}

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ put inout Bomb p → v {
    = p ( bomb `new` 0 )
    ( nurl_println `put: not reached` )
}

@ inner → v {
    : ~ Bomb a ( bomb `old` 1 )
    ( put a )
    ( nurl_println `inner: not reached` )
}

@ outer → v {
    : ~ Bomb a ( bomb `old` 1 )
    ( run `outer` \ → v { ( put a ) } )
    ( nurl_println ( nurl_str_cat `outer: a holds ` ( string_data . a tag ) ) )
}

@ main → i {
    ( run `inner` \ → v { ( inner ) } )
    ( outer )
    ^ 0
}
