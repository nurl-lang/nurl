// H233: a match on an enum a call handed over — `?? ( mk ) { Text t → … }` — left the enum with no owner: its cell and its payload leaked on every arm.
// Closed: such an enum gets an owner of its own for the rest of the scope, which drops it; its payload is lent to the arms.
// main (before this PR): LSan detected memory leaks.
$ `stdlib/core/string.nu`

: | Msg { Text String Quiet }

@ mk → Msg {
    ^ @ Msg { Text ( string_from `a string long enough to live on the heap` ) }
}

@ main → i {
    ?? ( mk ) { Text t → { ( nurl_println ( string_data t ) ) } Quiet → {} }
    ^ 0
}
