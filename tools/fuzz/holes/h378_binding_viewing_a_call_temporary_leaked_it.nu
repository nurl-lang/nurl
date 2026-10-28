// H378: a binding of a view of a call's temporary argument (`: s v ( first ( string_from … ) )`, `first` handing back `( string_data s )`) leaked the temporary: its drop waits for a call further out to consume the view, and a binding never is one — dropping it at the statement's end would have left the view dangling.
// Closed: a temporary a call's result may view that no call consumes is rejected once the module-end summaries say the caller owned it (resolve_view_temps, agora #138) — bind the argument to a name first.
// v0.79.1: accepted; LeakSanitizer reported the String and its buffer.
$ `stdlib/core/string.nu`

@ first String s → s { ^ ( string_data s ) }

@ main → i {
    : s v ( first ( string_from `a string long enough to own a heap buffer here` ) )
    ( nurl_println v )
    ^ 0
}
