// map: §2.10 | A2 | rejected | - | AGORA-428: a view a callee lends of a user enum's payload, kept while `?? g { GSome q → push }` grows it
// AGORA-428 (this shape, closed): refused - a change through a payload read in place as a part of the matched binding sweeps that binding too, so a lend of it ends (main 54e5c459: accepted)
$ `stdlib/core/string.nu`

: H { String name }
: | G { GNone GSome H }

@ name_of G g → s { ?? g { GSome p → { ^ ( string_data . p name ) } GNone → { ^ `` } } }

@ main → i {
    : ~ G g @ G { GSome @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } }
    : s v ( name_of g )
    ?? g { GSome q → { ( string_push_str . q name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } GNone → {} }
    ( nurl_println v )
    ^ 0
}
