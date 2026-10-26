// A call's temporary that gets an owner of its own for the rest of the
// scope — an enum a match takes and nothing binds (h233), a result read
// for a field it cannot give up (h329, h330) — is in the panic journal
// while that owner holds it: a panic before the scope ends releases it,
// once (docs/MEMORY.md §7.2). Before, neither was journaled: the unwind
// leaked it and its destructors never ran. A read run again on every
// round of a loop's condition holds one registration, not one per round:
// a stale one would release the previous round's value a second time.
// A match on such an enum in a loop's condition releases the round before
// (it leaked every round but the last), and one on a single arm of a `?`
// releases nothing on the other (its flag starts clear).
// Leak-clean under LSan (LSAN_DETECT_LEAKS=1 run_san_tests.sh).
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Conn {
    i fd
    String name
}

% Drop Conn {
    @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop conn ` ( string_data . c name ) ) ) }
}

// No `% Drop` of its own: a field that cannot be copied.
: Plain {
    Conn c
    String tag
}

@ mkp s n i fd → Plain {
    ^ @ Plain { @ Conn { fd ( string_from n ) } ( string_from `p` ) }
}

// A `% Drop` of its own: a String field is copied out, the rest stays.
: Wrap {
    String name
    i n
}

% Drop Wrap {
    @ drop sink Wrap w → v { ( nurl_println ( nurl_str_cat `drop wrap ` ( string_data . w name ) ) ) }
}

@ mkw s n → Wrap {
    ^ @ Wrap { ( string_from n ) 1 }
}

// An enum whose payload has a `% Drop`: the match owns it (h233).
: | Got { Some Conn None }

// …and one whose payload is a String.
: | Msg { Text String Quiet }

@ mkg s n → Got {
    ^ @ Got { Some @ Conn { 3 ( string_from n ) } }
}

@ mkm s n → Msg {
    ^ @ Msg { Text ( string_from n ) }
}

@ boom s why → v { ( panic why ) }

@ enum_arm → v {
    ?? ( mkg `matched` ) {
        Some c → { ( nurl_println ( string_data . c name ) ) ( boom `in arm` ) }
        None → {}
    }
}

@ enum_after → v {
    ?? ( mkg `after-match` ) {
        Some c → ( nurl_println ( string_data . c name ) )
        None → {}
    }
    ( boom `after match` )
}

@ msg_arm → v {
    ?? ( mkm `text` ) {
        Text t → { ( nurl_println ( string_data t ) ) ( boom `in text arm` ) }
        Quiet → {}
    }
}

@ field_bound → v {
    : Conn a . ( mkp `bound` 4 ) c
    ( nurl_println ( nurl_str_int . a fd ) )
    ( boom `bound` )
}

@ field_copy → v {
    : String s . ( mkw `copy` ) name
    ( nurl_println ( string_data s ) )
    ( boom `copy` )
}

// Every round reads again and releases the round before it; the panic
// comes on the third round, while that round's temporary is held.
@ field_loop → v {
    : ~ i k 0
    ~ < k . . ( mkp `loop` 9 ) c fd {
        = k + k 2
        ? >= k 6 { ( boom `loop` ) } {}
    }
}

// The same for an enum a loop's condition matches: each round releases
// the one before it (it overwrote it, and that one leaked), with or
// without a panic.
@ enum_loop b fail → v {
    : ~ i k 0
    ~ ?? ( mkg `cond` ) { Some c → < k 3 None → F } {
        = k + k 1
        ? & fail >= k 2 { ( boom `enum loop` ) } {}
    }
}

// A match on one arm of a `?` only: the other path reaches the scope's
// end with no enum, and releases nothing.
@ enum_one_arm b take → i {
    : i n ? take ?? ( mkg `one arm` ) { Some c → . c fd None → 0 } 5
    ^ n
}

@ guard s what ( @ v ) cl → v {
    : i before ( live )
    : !v PanicInfo r ( recover cl )
    ?? r {
        T _ → ( nurl_println `no panic` )
        F p → { ( nurl_println ( nurl_str_cat `caught ` ( string_data . p msg ) ) )
            ( panic_info_free p ) }
    }
    ( nurl_println ( nurl_str_cat3 what ` live ` ( nurl_str_int - ( live ) before ) ) )
}

@ main → i {
    // The first panic leaves the runtime one block it keeps for the next:
    // taken here, so each count below is the shape's own.
    : !v PanicInfo w ( recover \ → v { ( boom `warm` ) } )
    ?? w { T _ → {} F p → ( panic_info_free p ) }
    ( guard `enum_arm` \ → v { ( enum_arm ) } )
    ( guard `enum_after` \ → v { ( enum_after ) } )
    ( guard `msg_arm` \ → v { ( msg_arm ) } )
    ( guard `field_bound` \ → v { ( field_bound ) } )
    ( guard `field_copy` \ → v { ( field_copy ) } )
    ( guard `field_loop` \ → v { ( field_loop ) } )
    ( guard `enum_loop` \ → v { ( enum_loop F ) } )
    ( guard `enum_loop_panic` \ → v { ( enum_loop T ) } )
    ( guard `enum_one_arm` \ → v { ( nurl_println_int + ( enum_one_arm F ) ( enum_one_arm T ) ) } )
    ( nurl_println `end` )
    ^ 0
}
