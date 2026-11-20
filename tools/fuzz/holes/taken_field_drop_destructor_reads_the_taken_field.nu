// map: §2.1 | A2 | rejected | - | AGORA-929: a `% Drop` destructor uses a String field a sink took
// AGORA-929 (this shape, closed): refused - a sink may not take a field the struct's own % Drop reads (main 08e56f54: accepted, the destructor read the emptied field)
$ `stdlib/core/string.nu`

: Named { String s i n }

% Drop Named { @ drop Named c → v { ( string_push_str . c s `, dropped` ) ( nurl_println ( string_data . c s ) ) } }

@ eat sink String v → i { ^ ( string_len v ) }

@ main → i {
    : Named h @ Named { ( string_from `a name long enough to own a heap buffer of its own` ) 1 }
    : i k ( eat . h s )
    ^ 0
}
