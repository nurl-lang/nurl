// A binding read out of a field borrows that field, not its whole struct
// (h331): a call that writes the elements of one field leaves borrows of
// the others standing (std/p256_field.nu's scratch registers), a store
// replacing the very field the binding read hands it the old value, and
// a field read handed to a `sink` takes the field over.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Regs {
    ( Vec i ) a
    ( Vec i ) b
}

// Writes `out`'s first element: may change what `out` holds, nothing else.
@ put ( Vec i ) out i x → v { ( vec_put [i] out 0 x ) }

@ two_fields → i {
    : ~ ( Vec i ) xa ( vec_new [i] )
    ( vec_push [i] xa 1 )
    : ~ ( Vec i ) xb ( vec_new [i] )
    ( vec_push [i] xb 2 )
    : Regs r @ Regs { xa xb }
    : ( Vec i ) ra . r a
    : ( Vec i ) rb . r b
    ( put ra 10 )
    ( put rb + ( vec_at [i] ra 0 ) 5 )
    ^ + ( vec_at [i] ra 0 ) ( vec_at [i] rb 0 )
}

: Doc {
    String title
    i n
}

@ swap_title inout Doc d → String {
    : String old . d title
    = . d title ( string_from `new` )
    ^ old
}

@ keep sink String s → i { ^ ( string_len s ) }

@ main → i {
    ( nurl_println ( nurl_str_int ( two_fields ) ) )
    : ~ Doc d @ Doc { ( string_from `old` ) 1 }
    : String was ( swap_title d )
    ( nurl_println ( string_data was ) )
    ( nurl_println ( string_data . d title ) )
    : Doc e @ Doc { ( string_from `taken` ) 2 }
    : String t . e title
    ( nurl_println ( nurl_str_int ( keep t ) ) )
    ^ 0
}
