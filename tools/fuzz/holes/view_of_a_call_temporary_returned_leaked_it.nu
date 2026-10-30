// view_of_a_call_temporary_returned_leaked_it: a view of a call's temporary argument returned straight out (`^ ( first ( string_from … ) )`) leaked the temporary, as h378's binding did: the return consumes nothing — and dropping the temporary there would have handed the caller a dangling view.
// Closed: as h378 (resolve_view_temps, agora #138).
// v0.79.1: accepted; LeakSanitizer reported the String and its buffer.
// map: §1 | A2 | rejected | h380 | as h378, the view returned straight out (^ ( first ( string_from … ) ))
$ `stdlib/core/string.nu`

@ first String s → s { ^ ( string_data s ) }

@ direct → s { ^ ( first ( string_from `a string long enough to own a heap buffer here` ) ) }

@ main → i {
    ( nurl_println ( direct ) )
    ^ 0
}
