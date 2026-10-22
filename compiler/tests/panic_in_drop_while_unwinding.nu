// panic_in_drop_while_unwinding.nu — a double panic: a destructor panics
// while a panic's drops run (formal/CLAIM.md says how it is modelled).
//
// The panic in `body` drains the journal: `c`'s drop, then `b`'s, which
// panics again. That second panic is caught by the same `recover`: what
// is left (`a`) is still dropped, and the first panic — the cause — keeps
// its message. Before, the second message replaced the first and leaked it
// (LeakSanitizer, run_san_tests.sh), and the thread stayed in the drain's
// state for good: every later free went through a record that only grew,
// and a free of an address the drain had released and malloc reused was
// skipped. The loops after the recover run on a thread whose frees are
// ordinary again; the second recover shows the next panic is too.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
        ? == . b boom 1 { ( panic `panic in a drop` ) } {}
    }
}

@ body → v {
    : Bomb a @ Bomb { ( string_from `a` ) 0 }
    : Bomb b @ Bomb { ( string_from `b` ) 1 }
    : Bomb c @ Bomb { ( string_from `c` ) 0 }
    ( panic `the cause` )
}

@ again → v {
    : Bomb d @ Bomb { ( string_from `d` ) 0 }
    ( panic `a second, ordinary panic` )
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( body ) } )
    ?? r {
        T _ → { ( puts `no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `recovered: ` ( string_data . e msg ) ) ) }
    }
    : ~ i k 0
    : ~ i n 0
    ~ < k 100000 {
        : String s ( string_from `abcdefghijklmnop` )
        = n + n ( string_len s )
        = k + k 1
    }
    ( nurl_println ( nurl_str_cat `bytes: ` ( nurl_str_int n ) ) )
    : !v PanicInfo r2 ( recover \ → v { ( again ) } )
    ?? r2 {
        T _ → { ( puts `no panic` ) }
        F e2 → { ( nurl_println ( nurl_str_cat `recovered: ` ( string_data . e2 msg ) ) ) }
    }
    ^ 0
}
