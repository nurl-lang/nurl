// A destructor struct of two fields, raw text a view and a number, each read through the pairs by its destructor.
$ `stdlib/core/string.nu`

: P { s name i n }

% Drop P { @ drop P self → v { ( nurl_println . self name ) : i m . self n ( nurl_println_int m ) } }

@ main → i {
    : String s ( string_from `a name a two-field holder views` )
    : P p @ P { ( string_data s ) 7 }
    ^ 0
}
