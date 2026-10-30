// dyn_object_captured_by_a_closure_dropped_twice_by_a_panic: a trait object captured by a closure held in a struct, then a panic under `recover` in the same scope: the struct's drop dropped the closure's environment and the object in it, and the binding's journal registration, its drop flag read once when it was made, dropped the object again.
// Closed: a binding with a drop flag is journaled with the flag (nurl_journal_push_drop2), and the drain reads it: the capture cleared it.
// v0.78.0: accepted; ASan reported heap-use-after-free in the journal drain.
// map: §7.2 | A2 | runs-clean | h363 | a trait object captured by a closure held in a struct, then a recovered panic: the struct's drop dropped the environment and the object, and the binding's registration dropped it again
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: Holder { String s }

% Peek [T] { @ peek T self → i }

% Peek Holder { @ peek Holder h → i { ^ ( string_len . h s ) } }

@ boom → v { ( nurl_panic `boom` ) }

: Job { ( @ v ) run }

@ f → v {
    : %Peek d ( dyn Peek @ Holder { ( string_from `abc` ) } )
    : Job j @ Job { \ → v { : i _r ( peek d ) } }
    ( boom )
    : ( @ v ) r . j run
    ( r )
}

@ main → i {
    ?? ( recover \ → v { ( f ) } ) { T _ → { ( nurl_println `ok` ) } F e → { ( nurl_println ( string_data . e msg ) ) } }
    ^ 0
}
