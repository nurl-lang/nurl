// Reassignment and argument temporaries retain unwind ownership.
$ `stdlib/std/panic.nu`

@ crash_assignment → v {
    : ~ s value ( nurl_str_cat `old` ` allocation` )
    = value ( nurl_str_cat `new` ` allocation` )
    = value ? T `copied literal` `other literal`
    ( panic `assigned string` )
}

@ crash_slice_assignment → v {
    : ~ [i values [i | 1 2]
    = values [i | 3 4 5]
    ( panic `assigned slice` )
}

@ borrow_then_panic s value → v {
    ( panic value )
}

@ panic_argument → i {
    ( panic `later argument` )
    ^ 0
}

@ borrow_two s value i second → v {}

@ guard ( @ v ) work → v {
    ?? ( recover work ) {
        T _ → { ( nurl_exit 2 ) }
        F info → { ( panic_info_free info ) }
    }
}

@ main → i {
    ( guard \ → v { ( crash_assignment ) } )
    ( guard \ → v { ( crash_slice_assignment ) } )
    ( guard \ → v { ( borrow_then_panic ( nurl_str_cat `owned` ` argument` ) ) } )
    ( guard \ → v { ( borrow_two ( nurl_str_cat `first` ` argument` ) ( panic_argument ) ) } )
    ( nurl_print `0\n` )
    ^ 0
}
