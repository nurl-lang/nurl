// map: §2.14 | A2 | rejected | - | AGORA-929: adversarial neighbour of the destructor-as-effect rule (a280_unsafe_nested_holder)
// AGORA-929 (this shape, closed): refused - a sink may not take a field the struct's own % Drop reads (main 08e56f54: accepted, the destructor read the emptied field)
$ `stdlib/core/string.nu`

: Named { String s i n }
: Outer { Named m i z }

% Drop Named { @ drop Named c → v { ( string_push_str . c s `, dropped` ) ( nurl_println ( string_data . c s ) ) } }

@ eat sink String v → i { ^ ( string_len v ) }

@ main → i {
    : Outer o @ Outer { @ Named { ( string_from `a name long enough to own a heap buffer of its own` ) 1 } 2 }
    : i k ( eat . . o m s )
    ^ 0
}
