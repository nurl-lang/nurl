// panic_in_drop_of_vec_element.nu — an element's destructor panics while
// its Vec releases its elements (Agora #608; formal/CLAIM.md, the drain).
//
// The panic does not end the release: the elements after the panicking one
// still run their destructors, in index order and once each, the buffer
// and the Vec are freed, and only then does the panic go on to its
// `recover`. Before, the runtime's element loop was simply left: `drop c`
// never ran, and c, the buffer and the control block leaked
// (LeakSanitizer, run_san_tests.sh). The same loop is behind a Vec in a
// Vec, and `vec_truncate` / `vec_clear` drop their tail the same way.
//
// `two_bombs`: the destructor of a LATER element panics too, inside the
// first panic's drain. The release goes on again, and the first panic —
// the cause — keeps its message.

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

@ three s a s b s c i boom → ( Vec Bomb ) {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb a 0 ) )
    ( vec_push [Bomb] v ( bomb b boom ) )
    ( vec_push [Bomb] v ( bomb c 0 ) )
    ^ v
}

// The Vec's own drop, at its binding's end.
@ whole → v {
    : ( Vec Bomb ) v ( three `a` `b` `c` 1 )
    ( nurl_println `whole: built` )
}

// Two of the elements panic: a panic inside the first one's drain.
@ two_bombs → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `a` 0 ) )
    ( vec_push [Bomb] v ( bomb `b` 1 ) )
    ( vec_push [Bomb] v ( bomb `c` 1 ) )
    ( vec_push [Bomb] v ( bomb `d` 0 ) )
}

// The elements `vec_truncate` drops; `keep` stays the Vec's, and is
// dropped with it when the panic unwinds the binding.
@ truncated → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `keep` 0 ) )
    ( vec_push [Bomb] v ( bomb `a` 0 ) )
    ( vec_push [Bomb] v ( bomb `b` 1 ) )
    ( vec_push [Bomb] v ( bomb `c` 0 ) )
    : b _t ( vec_truncate [Bomb] v 1 )
    ( nurl_println `truncated: not reached` )
}

@ cleared → v {
    : ~ ( Vec Bomb ) v ( three `a` `b` `c` 1 )
    ( vec_clear [Bomb] v )
    ( nurl_println `cleared: not reached` )
}

// A Vec of Vecs: the inner release is left by the panic, then the outer.
@ nested → v {
    : ~ ( Vec ( Vec Bomb ) ) vv ( vec_new [( Vec Bomb )] )
    ( vec_push [( Vec Bomb )] vv ( three `a` `b` `c` 1 ) )
    ( vec_push [( Vec Bomb )] vv ( three `d` `e` `f` 0 ) )
}

// A truncate that panics inside a `recover` of its own leaves the Vec
// short and usable: the caller goes on with it.
@ survives → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `keep` 0 ) )
    ( vec_push [Bomb] v ( bomb `a` 1 ) )
    ( vec_push [Bomb] v ( bomb `b` 0 ) )
    : !v PanicInfo r ( recover \ → v { : b _t ( vec_truncate [Bomb] v 1 ) } )
    ?? r {
        T _ → { ( puts `no panic` ) }
        F e → { ( nurl_println ( nurl_str_cat `survives: recovered: ` ( string_data . e msg ) ) ) }
    }
    ( nurl_println ( nurl_str_cat `survives: len ` ( nurl_str_int ( vec_len [Bomb] v ) ) ) )
    ( vec_push [Bomb] v ( bomb `late` 0 ) )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `whole` \ → v { ( whole ) } )
    ( run `two_bombs` \ → v { ( two_bombs ) } )
    ( run `truncated` \ → v { ( truncated ) } )
    ( run `cleared` \ → v { ( cleared ) } )
    ( run `nested` \ → v { ( nested ) } )
    ( survives )
    // The thread's frees are ordinary again after all of that.
    : ~ i k 0
    : ~ i n 0
    ~ < k 100000 {
        : String s ( string_from `abcdefghijklmnop` )
        = n + n ( string_len s )
        = k + k 1
    }
    ( nurl_println ( nurl_str_cat `bytes: ` ( nurl_str_int n ) ) )
    ^ 0
}
