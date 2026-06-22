// recover_unwind.nu — panic-unwind allocation journal (docs/MEMORY.md §7).
//
// A panic longjmps to the nearest `recover`, skipping the scope-exit
// `nurl_free`s the compiler queued between. The runtime journal records
// every owned auto-drop allocation made inside a recover extent and frees
// the still-live ones before the longjmp, so they no longer leak. This
// test exercises the three covered obligation kinds and the escape-
// soundness boundary; run under LSan (LSAN_DETECT_LEAKS=1) it is
// leak-clean, and under ASan it is free of the double-free / use-after-
// free that an unsound unwind would cause.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Resp { s body i code }

// A user `% Drop` type whose typed destructor frees a malloc'd buffer.
: Handle { * u buf }

% Drop ( Handle ) { @ drop Handle h → v { ( nurl_free # s . h buf ) } }

// Owned raw string scratch, freed by the unwind (not leaked).
@ crash_string → v {
    : s scratch ( nurl_str_cat `string-scratch-` `reclaimed-on-panic` )
    ( nurl_print scratch ) ( nurl_print `\n` )
    ( panic `s` )
}

// User `% Drop` value: its typed destructor is replayed by the unwind,
// including one already dropped in a prior loop iteration (no double-drop).
@ crash_drop → v {
    : ~ i k 0
    ~ < k 2 {
        : Handle tmp @ Handle { # *u ( malloc 24 ) }
        ( nurl_print `handle iter\n` )
        = k + k 1
    }
    : Handle live @ Handle { # *u ( malloc 24 ) }
    ( nurl_print `handle live\n` )
    ( panic `d` )
}

// Owned slice scratch.
@ crash_slice → v {
    : [i xs [i | 1 2 3 4 5 6 7 8 9 10]
    ( nurl_print `slice built\n` )
    ( panic `sl` )
}

// Owned struct-field scratch + earlier loop allocation (stale-entry test:
// each iteration's string is freed mid-body, so its journal entry is gone
// by the time the panic drains — no double free).
@ crash_struct → v {
    : ~ i k 0
    ~ < k 3 {
        : s t ( nurl_str_cat `iter-` `buffer` )
        ( nurl_print t ) ( nurl_print `\n` )
        = k + k 1
    }
    : Resp r @ Resp { ( nurl_str_cat `field-` `under-construction` ) 200 }
    ( nurl_print ( nurl_str_int . r code ) ) ( nurl_print `\n` )
    ( panic `st` )
}

@ guard ( @ v ) cl → v {
    : !v PanicInfo r ( recover cl )
    ?? r {
        T _ → ( nurl_print `ok\n` )
        F p → { ( nurl_print `caught ` ) ( nurl_print ( string_data . p msg ) ) ( nurl_print `\n` )
            ( panic_info_free p ) }
    }
}

@ main → i {
    ( guard \ → v { ( crash_string ) } )
    ( guard \ → v { ( crash_slice ) } )
    ( guard \ → v { ( crash_struct ) } )
    ( guard \ → v { ( crash_drop ) } )

    // Escape soundness: a struct built inside the closure is moved into a
    // by-ref-captured caller binding, THEN the closure panics. The journal
    // must NOT free the escaped field (the caller owns it now) — the read
    // below would be a use-after-free if it did.
    // `out` starts with a non-owned (literal) body so the reassignment
    // below frees nothing on the caller side — the test isolates the
    // escape-into-byref-capture path.
    : ~ Resp out @ Resp { `none` 500 }
    : !v PanicInfo re ( recover \ → v {
        : Resp tmp @ Resp { ( nurl_str_cat `escaped-` `field` ) 201 }
        = out tmp
        ( panic `esc` )
    } )
    ?? re { T _ → {} F p → ( panic_info_free p ) }
    // The escaped field survived the panic (the journal forgot it on the
    // escaping assignment): it reads back intact and is ours to free —
    // a dangling pointer would fault here. Freeing it keeps the test
    // LSan-clean (the caller owns the escaped value).
    ( nurl_print `out.code=` ) ( nurl_print ( nurl_str_int . out code ) ) ( nurl_print `\n` )
    ( nurl_print `out.body=` ) ( nurl_print . out body ) ( nurl_print `\n` )
    ( nurl_free # s . out body )

    ( nurl_print `alive\n` )
    ^ 0
}
