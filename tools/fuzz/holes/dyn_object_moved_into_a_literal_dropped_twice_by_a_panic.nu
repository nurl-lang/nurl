// dyn_object_moved_into_a_literal_dropped_twice_by_a_panic: a trait object moved into a struct literal (`: Wrap w @ Wrap { d }`), then a panic under `recover` in the same scope: the binding's journal registration had read its drop flag once, when it was made, and still said it owned the box — the drain dropped the object through `d` and again through `w`.
// Closed: a binding with a drop flag is journaled with the flag (nurl_journal_push_drop2), and the drain reads it: the move cleared it, so only `w` drops the object.
// v0.78.0: accepted; ASan reported heap-use-after-free in the journal drain.
// map: §7.2 | A2 | runs-clean | h361 | a trait object moved into a struct literal, then a recovered panic: its journal registration had read the drop flag at the push and dropped the box the struct dropped too; a flagged binding is journaled with its flag, read at the drain
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: Holder { String s }

% Peek [T] { @ peek T self → i }

% Peek Holder { @ peek Holder h → i { ^ ( string_len . h s ) } }

@ boom → v { ( nurl_panic `boom` ) }

: Wrap { % Peek p }

@ f → v {
    : %Peek d ( dyn Peek @ Holder { ( string_from `abc` ) } )
    : Wrap w @ Wrap { d }
    ( boom )
    : i _r ( peek . w p )
}

@ main → i {
    ?? ( recover \ → v { ( f ) } ) { T _ → { ( nurl_println `ok` ) } F e → { ( nurl_println ( string_data . e msg ) ) } }
    ^ 0
}
