// closure_field_store_drops_old_value.nu — inside a closure, a field store
// to an option field of a struct the closure captured by pointer, or of a
// struct of its own, drops the value it replaces (Agora #731).
//
// Before, the option field's old value was dropped only outside a closure
// body: inside one it leaked on every store (a String or Vec field was
// released; an option or a result of one was not).

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
        ? == . b boom 1 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {}
    }
}

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { ? Bomb o i n }

@ main → i {
    : ~ Holder h @ Holder { @ ?Bomb { T ( bomb `captured.0` 0 ) } 0 }
    : ( @ v ) set \ → v { = . h o @ ?Bomb { T ( bomb `captured.1` 0 ) } }
    ( set )
    ( set )
    : ( @ v ) own \ → v {
        : ~ Holder l @ Holder { @ ?Bomb { T ( bomb `own.0` 0 ) } 0 }
        = . l o @ ?Bomb { T ( bomb `own.1` 0 ) }
    }
    ( own )
    // The old value's destructor panics: the new value stays in the field
    // (Agora #621) and is dropped with `h`.
    : !v PanicInfo r ( recover \ → v {
        = . h o @ ?Bomb { T ( bomb `captured.2` 1 ) }
        = . h o @ ?Bomb { T ( bomb `captured.3` 0 ) }
    } )
    ( nurl_println `done` )
    ^ 0
}
