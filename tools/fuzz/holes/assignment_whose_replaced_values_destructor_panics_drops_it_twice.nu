// assignment_whose_replaced_values_destructor_panics_drops_it_twice: `= b new` dropped the value `b` held in place, before the store, with `b` still registered in the panic journal as holding it: when that value's destructor panicked under `recover`, the unwind dropped it a second time, and the new value was nobody's.
// Closed: an assignment takes the old value out first — the new value is stored, then the old one is dropped from a temporary (mem_replaced_drop / gen_assign) — so a panic in its destructor finds the target holding the new value, which is dropped once (agora #621).
// main (before this PR): AddressSanitizer heap-use-after-free in drop__Bomb, from the journal drain.
// map: §7.6 | A2 | runs-clean | - | agora #621: the value an assignment replaces was dropped in place before the store; a panic in its destructor made the unwind drop it again and lose the new value
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

@ local → v {
    : ~ Bomb a ( bomb `old` 1 )
    = a ( bomb `new` 0 )
    ( nurl_println `local: not reached` )
}

: Holder { Bomb b String name }

@ whole → v {
    : ~ Holder h @ Holder { ( bomb `old` 1 ) ( string_from `n` ) }
    = h @ Holder { ( bomb `new` 0 ) ( string_from `m` ) }
    ( nurl_println `whole: not reached` )
}

@ captured → v {
    : ~ Bomb a ( bomb `old` 1 )
    : ( @ v ) f \ → v { = a ( bomb `new` 0 ) ( nurl_println `f: not reached` ) }
    ( f )
    ( nurl_println `captured: not reached` )
}

@ main → i {
    ( run `local` \ → v { ( local ) } )
    ( run `whole` \ → v { ( whole ) } )
    ( run `captured` \ → v { ( captured ) } )
    ^ 0
}
