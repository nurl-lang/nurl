// A library handle's drop hook (`X_drop sink X h`) is its receiver's
// destructor, as a `% Drop` impl is: the receiver is not dropped again on
// the way out (that would run the hook again, forever) — its fields are,
// once the hook returns. So a safe hook that only observes the value needs
// no `mem_forget` (unsafe-only), and runs exactly once per value.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Note { String text ( Vec String ) tags }

@ Note_drop sink Note h → v {
    ( nurl_print `drop ` ) ( nurl_print ( string_data . h text ) )
    ( nurl_print ` tags=` ) ( nurl_print_int ( vec_len [String] . h tags ) ) ( nurl_println `` )
}

@ mk s t → Note {
    : Note n @ Note { ( string_from t ) ( vec_new [String] ) }
    ( vec_push [String] . n tags ( string_from `a` ) )
    ^ n
}

@ main → i {
    : Note a ( mk `first` )
    : Note b ( mk `second` )
    : ( Vec Note ) all ( vec_new [Note] )
    ( vec_push [Note] all ( mk `in-a-vec` ) )
    ( nurl_println `end` )
    ^ 0
}
