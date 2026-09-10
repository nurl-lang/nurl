// Valid counterpart: heap access before free, closure captures by value.
: Counter { i n i max }

@ make → ( @ i ) {
    : Counter c @ Counter { 41 100 }
    ^ \ → i { ^ + . c n 1 }
}

@ main → i {
    : *u p # *u ( nurl_alloc 8 )
    = . p 0 # u 42
    ( nurl_println_int # i . p 0 )
    ( nurl_free # s p )
    : ( @ i ) f ( make )
    ( nurl_println_int ( f ) )
    ^ 0
}
