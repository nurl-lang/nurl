// A String handed to a sink in a loop while a destructor value views it (the checker refuses it).
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ take sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String s ( string_from `a string handed away in a loop while w views it` )
    : W w @ W { ( string_data s ) }
    : ~ i k 0
    ~ < k 1 {
        = k + ( take s ) 1
    }
    ^ 0
}
