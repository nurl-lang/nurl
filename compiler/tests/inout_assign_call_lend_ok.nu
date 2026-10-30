// inout_assign_call_lend_ok.nu — an `inout` parameter assigned a call's
// value that lends one of this function's locals (`= io ( gets w )`), or a
// block or a try ending in such a call, or a local struct's field: the locals are gone when the
// function returns and the caller keeps the value, so it gets a copy and
// its old value is dropped (agora #196).

$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s i n }

% Drop W { @ drop W w → v { ( nurl_print `drop ` ) ( nurl_println_int . w n ) } }

@ gets W w → String { ^ . w s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw s t i n → W { ^ @ W { ( string_from t ) n } }

@ by_call inout String io → v {
    : W w ( mkw `lent by a call` 1 )
    = io ( gets w )
}

@ by_block inout String io → v {
    = io {
        : W w ( mkw `lent through a block` 2 )
        ( gets w )
    }
}

@ by_try inout String io → !i E {
    : W w ( mkw `lent through a try` 3 )
    = io \ ( getr w )
    ^ @ !i E { T 0 }
}

@ by_field inout String io → v {
    : W w ( mkw `a local struct's field` 4 )
    = io . w s
}

@ main → i {
    : ~ String t ( string_from `start` )
    ( by_call t )
    ( nurl_println ( string_data t ) )
    ( by_block t )
    ( nurl_println ( string_data t ) )
    ?? ( by_try t ) { T n → ( nurl_println ( string_data t ) ) F _ → ( nurl_println `bad` ) }
    ( by_field t )
    ( nurl_println ( string_data t ) )
    ^ 0
}
