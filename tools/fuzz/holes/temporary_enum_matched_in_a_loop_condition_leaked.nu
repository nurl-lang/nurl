// temporary_enum_matched_in_a_loop_condition_leaked: an enum a call hands over, matched in a loop's condition (`~ ?? ( mk ) { … } { … }`), gets an owner of its own for the rest of the scope (h233) — the scope around the loop. Every round stored its enum over the round before's without releasing it: only the last was dropped, and every other leaked, payload and cell, its destructor never run.
// Closed: the owner's flag starts clear on every path, and each round releases the round before (and ends its journal registration) before storing its own, as a field read out of a call's result in a loop's condition does (h330).
// main (before this PR): LeakSanitizer reported each round's payload and cell but the last.
// map: §7.1 | A2 | runs-clean | h335 | an enum a call handed over, matched in a loop's condition: each round overwrote the one before in the owner's slot, so every round but the last leaked; each round releases the one before now
$ `stdlib/core/string.nu`

: Conn {
    i fd
    String name
}

% Drop Conn {
    @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) }
}

: | Got { Some Conn None }

@ mkg i k → Got {
    ^ @ Got { Some @ Conn { k ( string_from `round` ) } }
}

@ main → i {
    : ~ i k 0
    ~ ?? ( mkg k ) { Some c → < . c fd 4 None → F } { = k + k 1 }
    ( nurl_print `rounds: ` ) ( nurl_println_int k )
    ^ 0
}
