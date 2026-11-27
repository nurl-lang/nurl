// A String given a new value while a destructor value views it (the checker refuses it).
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ~ String s ( string_from `a string given a new value while w still views it` )
    : W w @ W { ( string_data s ) }
    = s ( string_from `another` )
    ^ 0
}
