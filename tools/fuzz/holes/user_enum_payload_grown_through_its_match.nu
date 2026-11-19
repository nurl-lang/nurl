// map: §2.10 | A2 | rejected | - | AGORA-428: a view of a user enum's payload kept while `?? g { GSome q → push }` grows it
// AGORA-428 (this shape): refused on main 4db4cf5b by both nurlc and tools/ncore - closed by earlier work (AGORA-842's payload-cursor owners, AGORA-580, AGORA-428's copies); moved out of the open probes
$ `stdlib/core/string.nu`

: H { String name }
: | G { GNone GSome H }

@ main → i {
    : ~ G g @ G { GSome @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } }
    : s v ?? g { GSome q → ( string_data . q name ) GNone → `none` }
    ?? g { GSome q → { ( string_push_str . q name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } GNone → {} }
    ( nurl_println v )
    ^ 0
}
