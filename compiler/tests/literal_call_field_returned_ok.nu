// literal_call_field_returned_ok.nu — a returned literal's field (or an
// option's payload) from a call that lends it out of a local is copied, as
// `^ ( g x )` copies it: the local is dropped on the way out (agora #189).
// So is one from a block ending in such a call, a fall-off literal's and a
// nested literal's, and such a block handed to a `sink`; a lend of a
// parameter stays a lend.

$ `stdlib/core/string.nu`

: W { String s }

: P { W w i n }

@ gets W w → String { ^ . w s }

@ mkw s t → W { ^ @ W { ( string_from t ) } }

@ field → W {
    : W w ( mkw `a field lent out of a local` )
    ^ @ W { ( gets w ) }
}

@ block_field → W {
    ^ @ W { {
            : W w ( mkw `a field from a block's local` )
            ( gets w )
        } }
}

@ payload → ?String {
    : W w ( mkw `an option payload lent out of a local` )
    ^ @ ?String { T ( gets w ) }
}

@ fall_off → W {
    : W w ( mkw `a fall-off literal's field` )
    @ W { ( gets w ) }
}

@ nested → P {
    : W w ( mkw `a nested literal's field` )
    ^ @ P { @ W { ( gets w ) } 1 }
}

@ param W w → W { ^ @ W { ( gets w ) } }

@ keep sink String x → i { ^ ( string_len x ) }

@ main → i {
    ( nurl_println ( string_data . ( field ) s ) )
    ( nurl_println ( string_data . ( block_field ) s ) )
    ?? ( payload ) { T x → ( nurl_println ( string_data x ) ) F → ( nurl_println `none` ) }
    ( nurl_println ( string_data . ( fall_off ) s ) )
    : P p ( nested )
    ( nurl_println ( string_data . . p w s ) )
    : W w ( mkw `a parameter's field, lent back` )
    : W a ( param w )
    ( nurl_println ( string_data . a s ) )
    // (…and a block's lend of its own local handed to a `sink`: a copy.)
    ( nurl_println_int ( keep {
        : W bw ( mkw `a block's local handed to a sink` )
        ( gets bw )
    } ) )
    ^ 0
}
