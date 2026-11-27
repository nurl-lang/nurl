// A destructor value moved into another binding: each binding a destructor frame of its own.
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : String s ( string_from `a view held by a holder moved into another binding` )
    : W w @ W { ( string_data s ) }
    : W w2 w
    ^ 0
}
