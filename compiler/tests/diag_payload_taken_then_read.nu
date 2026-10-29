// diag_payload_taken_then_read.nu — an arm that hands out a payload of an
// enum or an option this function owns takes it out (agora #175). On that
// path the enum or option is moved, so reading it again is an error. Read
// after the value ended, it read freed memory.

$ `stdlib/core/string.nu`

: | E {
    S String
    NoVal
}

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ enum_read_after → i {
    : E e @ E { S ( mk ) }
    : String t ?? e { S s → s NoVal → ( mk ) }
    ?? e { S s → { ( nurl_println ( string_data s ) ) } NoVal → {} }
    ^ ( string_len t )
}

@ option_read_after_its_taker_ended → i {
    : ?String o @ ?String { T ( mk ) }
    {
        : String t ?? o { T s → s F → ( mk ) }
        ( nurl_println ( string_data t ) )
    }
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}

@ main → i { ^ 0 }
