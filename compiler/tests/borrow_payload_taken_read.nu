// borrow_payload_taken_read.nu — freeing a field of a match payload takes
// the payload apart: the rest of it is the arm's, and the option binding
// is left with that field emptied. Reading the option after the match, on
// the path that took it, read an emptied handle (a SEGV at run time); it
// is a use of a moved value now.

$ `stdlib/core/string.nu`

: Tagged { String name i n }

@ main → i {
    : ?Tagged o @ ?Tagged { T @ Tagged { ( string_from `abc` ) 1 } }
    ?? o { T t → ( string_free . t name ) F → {} }
    ?? o { T t → ( nurl_print ( string_data . t name ) ) F → {} }
    ^ 0
}
