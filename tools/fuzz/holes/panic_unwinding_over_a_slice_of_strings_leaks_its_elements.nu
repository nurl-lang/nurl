// panic_unwinding_over_a_slice_of_strings_leaks_its_elements: agora #509 — under `recover`, a panic that unwound over an owned slice freed its buffer through the journal and left the elements it owned (each String's buffer); a slice temporary in the argument list of the call that panicked was not journaled at all.
// Closed: a slice binding and a slice temporary are journaled as handles (mem_journal_push_temp, __hjdrop_fn): the unwind runs the slice's own drop, elements first.
// main (before this PR): LeakSanitizer, the Strings of `sl` and both argument temporaries.
// map: §7.2 | A2 | runs-clean | - | agora #509: a panic unwinding over an owned slice freed its buffer but not its elements; a slice temporary in the panicking call's arguments leaked whole
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

@ boom i k → i {
    : [String sl [String | ( string_from `a string in a slice literal when a panic unwinds over it` )]
    ? > k 0 { ( panic `boom` ) } {}
    ~ x sl { ( nurl_println ( string_data x ) ) }
    ^ 0
}

@ boom2 i k [String a → v {
    ? > k 0 { ( panic `boom` ) } {}
}

@ mk → [String {
    ^ [String | ( string_from `a long enough string to be on the heap, one` )]
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { : i _n ( boom 1 ) } )
    ?? r {
        T _ → {}
        F p → { ( nurl_println `recovered` ) ( panic_info_free p ) }
    }
    : !v PanicInfo r2 ( recover \ → v { ( boom2 1 ( mk ) ) } )
    ?? r2 {
        T _ → {}
        F p → { ( nurl_println `recovered` ) ( panic_info_free p ) }
    }
    : !v PanicInfo r3 ( recover \ → v { ( boom2 1 [String | ( string_from `a literal with a long string on the heap, yes` )] ) } )
    ?? r3 {
        T _ → {}
        F p → { ( nurl_println `recovered` ) ( panic_info_free p ) }
    }
    ^ 0
}
