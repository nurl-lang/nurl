// call_temporary_owner_skipped_by_a_panic: a call's result that gets an owner of its own for the rest of the scope — an enum a match takes and nothing binds (h233), a result read for a field it cannot give up (h329, h330) — was never in the panic journal. A panic before the scope ended skipped its drop, and nothing else held it: the enum's payload and cell, the struct and its fields leaked, and their destructors never ran.
// Closed: the owner is journaled by its slot with its drop flag once the value and the flag are in place (mem_journal_push_tmpown), and the scope's end forgets it by slot. A read run again in a loop's condition forgets the round before's registration before releasing it, so one owner holds one registration.
// main (before this PR): LeakSanitizer reported the enum's payload and cell, and the struct's fields, on every panicking call.
// map: §7.2 | A2 | runs-clean | h334 | a call's result given an owner for the rest of the scope (h233's matched enum, h329/h330's field read) was never journaled: a panic before the scope ended leaked it and skipped its destructors; journaled once by its slot now
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: Conn {
    i fd
    String name
}

% Drop Conn {
    @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) }
}

: | Got { Some Conn None }

// A field that cannot be copied: the result is lent, not taken apart.
: Plain {
    Conn c
    String tag
}

@ mkg i k → Got {
    ^ @ Got { Some @ Conn { k ( string_from `enum` ) } }
}

@ mkp i k → Plain {
    ^ @ Plain { @ Conn { k ( string_from `field` ) } ( string_from `tag` ) }
}

@ boom i k → v {
    ? > k 2 { ( panic `too big` ) } {}
}

@ by_match i k → v {
    ?? ( mkg k ) {
        Some c → ( boom . c fd )
        None → {}
    }
}

@ by_field i k → v {
    : Conn c . ( mkp k ) c
    ( boom . c fd )
}

@ main → i {
    : ~ i caught 0
    : ~ i k 0
    ~ < k 6 {
        : !v PanicInfo r ( recover \ → v { ( by_match k ) ( by_field k ) } )
        ?? r { T _ → {} F p → { = caught + caught 1 ( panic_info_free p ) } }
        = k + k 1
    }
    ( nurl_print `caught: ` ) ( nurl_println_int caught )
    ^ 0
}
