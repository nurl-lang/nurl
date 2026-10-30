// dyn_object_given_to_a_sink_dropped_twice_by_a_panic: a trait object handed to a `sink` parameter, then a panic under `recover` in the caller's scope: the callee dropped the object, and the caller's journal registration, its drop flag read once when it was made, dropped it again.
// Closed: a binding with a drop flag is journaled with the flag (nurl_journal_push_drop2), and the drain reads it: the hand-over cleared it.
// v0.78.0: accepted; ASan reported heap-use-after-free in the journal drain.
// map: §7.2 | A2 | runs-clean | h362 | a trait object handed to a sink parameter, then a recovered panic in the caller: the callee dropped it and the caller's registration, its flag read at the push, dropped it again
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: Holder { String s }

% Peek [T] { @ peek T self → i }

% Peek Holder { @ peek Holder h → i { ^ ( string_len . h s ) } }

@ boom → v { ( nurl_panic `boom` ) }

@ take sink %Peek d → v { : i _r ( peek d ) }

@ f → v {
    : %Peek d ( dyn Peek @ Holder { ( string_from `abc` ) } )
    ( take d )
    ( boom )
}

@ main → i {
    ?? ( recover \ → v { ( f ) } ) { T _ → { ( nurl_println `ok` ) } F e → { ( nurl_println ( string_data . e msg ) ) } }
    ^ 0
}
