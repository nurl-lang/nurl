// field_store_whose_replaced_values_destructor_panics_drops_it_twice: `= . h b new` dropped the field's old value in place before the store, inside a struct the panic journal still held whole: when that destructor panicked under `recover`, the unwind dropped the struct with the old field value in it — a second time. A slice element store `= . a k new` lost the new value and the rest the same way.
// Closed: an assignment takes the old value out first — the new value is stored, then the old one is dropped from a temporary (mem_replaced_drop / gen_assign) — so a panic in its destructor finds the target holding the new value, which is dropped once (agora #621).
// main (before this PR): AddressSanitizer heap-use-after-free (`field`, `nested`, `through`); LeakSanitizer (`element`).
// map: §7.6 | A2 | runs-clean | - | agora #621: a field store or a slice element store dropped the replaced value in place; a panic in its destructor made the unwind drop it again with the struct
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

: Holder { Bomb b String name }

@ field → v {
    : ~ Holder h @ Holder { ( bomb `old` 1 ) ( string_from `n` ) }
    = . h b ( bomb `new` 0 )
    ( nurl_println `field: not reached` )
}

: Outer { Holder h i n }

@ nested → v {
    : ~ Outer o @ Outer { @ Holder { ( bomb `old` 1 ) ( string_from `n` ) } 1 }
    = . . o h b ( bomb `new` 0 )
    ( nurl_println `nested: not reached` )
}

@ put_field inout Holder p → v {
    = . p b ( bomb `new` 0 )
    ( nurl_println `put_field: not reached` )
}

@ through → v {
    : ~ Holder h @ Holder { ( bomb `old` 1 ) ( string_from `n` ) }
    ( put_field h )
    ( nurl_println `through: not reached` )
}

@ element → v {
    : ~ [Bomb a [Bomb | ( bomb `x` 0 ) ( bomb `old` 1 ) ( bomb `z` 0 )]
    : i k 1
    = . a k ( bomb `new` 0 )
    ( nurl_println `element: not reached` )
}

@ main → i {
    ( run `field` \ → v { ( field ) } )
    ( run `nested` \ → v { ( nested ) } )
    ( run `through` \ → v { ( through ) } )
    ( run `element` \ → v { ( element ) } )
    ^ 0
}
