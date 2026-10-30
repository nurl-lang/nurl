// option_field_replaced_leaks: replacing an option field of a struct the function owns (`= . r note @ ?String { … }`), or of an `inout` struct, stored the new option over the old one without dropping it: the old string leaked on every store.
// Closed: a field store that replaces an option or a result that owns something drops what the field held, as it does a String or a Vec field (__fs_drop_replaced).
// main (before this PR): LeakSanitizer, one string per replaced option.
// map: §7.1 | A2 | runs-clean | h198 | replacing an option struct field does not drop old payload: leak
$ `stdlib/core/string.nu`

: Rec { String name ? String note }

@ set_note inout Rec r s n → v { = . r note @ ?String { T ( string_from n ) } }

@ main → i {
    : ~ Rec r @ Rec { ( string_from `a name, long enough for the heap` ) @ ?String { F } }
    = . r note @ ?String { T ( string_from `a note, long enough for the heap` ) }
    = . r note @ ?String { T ( string_from `another note, long enough for the heap` ) }
    ( set_note r `a third note, long enough for the heap` )
    ( set_note r `a fourth note, long enough for the heap` )
    ( nurl_println ( string_data . r name ) )
    ^ 0
}
