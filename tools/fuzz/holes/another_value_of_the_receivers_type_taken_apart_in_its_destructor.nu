// another_value_of_the_receivers_type_taken_apart_in_its_destructor: AGORA-929 (CodeRabbit on github#2110) — inside `Holder`'s `% Drop`, a sink takes `. other buf` of a separate local `Holder`, whose own destructor then reads the emptied field
// map: §2.14 | A2 | rejected | - | AGORA-929: a destructor taking a field of another value of its type
$ `stdlib/core/string.nu`

: Holder { String buf i n }

@ eat sink String v → i { ^ ( string_len v ) }

% Drop Holder { @ drop Holder c → v {
        ( nurl_println ( string_data . c buf ) )
        ? > . c n 0 {
            : Holder other @ Holder { ( string_from `another string long enough to own a heap buffer` ) 0 }
            : i k ( eat . other buf )
        } {}
    } }

@ main → i {
    : Holder h @ Holder { ( string_from `a name long enough to own a heap buffer of its own` ) 1 }
    ^ 0
}
