// OPEN in 0.72.0 — a `% Drop` impl that assigns a new value to a field of its receiver leaks the old one.
// The impl stores ( string_from `replaced` ) into `. h text` with a plain field store: the String `orig`
// the field held is overwritten without being released, and the drop glue at the end of the impl
// releases only `replaced`. The compiler warns that the store lands in the by-value parameter's own
// copy, but accepts it.
// LSan: detected memory leaks — the `orig` String (24-byte control block from string_from, 8-byte buffer).
$ `stdlib/core/string.nu`

: Note { String text i n }

% Drop Note { @ drop sink Note h → v {
        = . h text ( string_from `replaced` )
        ( puts ( string_data . h text ) )
    } }

@ main → i {
    : Note x @ Note { ( string_from `orig` ) 1 }
    ( puts `ran` )
    ^ 0
}
