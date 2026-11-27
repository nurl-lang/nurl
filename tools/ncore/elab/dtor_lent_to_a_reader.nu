// A destructor value lent to a function that reads its field (a read-only destructor parameter).
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ peek W w → v { ( nurl_println . w v ) }

@ main → i {
    : String s ( string_from `a holder lent to a function that reads its view` )
    : W w @ W { ( string_data s ) }
    ( peek w )
    ^ 0
}
