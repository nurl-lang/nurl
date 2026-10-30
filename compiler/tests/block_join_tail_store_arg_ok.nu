// block_join_tail_store_arg_ok.nu — a value block ending in a `?` / `??` join
// at a store or argument: judged as that join, reading its ownership phi
// rather than being treated as "lent always" (which leaked fresh arms) or
// ignored (which caused UAF over an inout parameter; agora #199).

$ `stdlib/core/string.nu`

: W { String s }

@ mkw s t → W { ^ @ W { ( string_from t ) } }

@ gets W w → String { ^ . w s }

: H { String s }

@ slen String s → i {
    ^ ( string_len s )
}

// Inout assignment: arm lending a local is cloned, fresh arm moves
@ put_inout inout String o b c → v {
    : W w ( mkw `local string` )
    = o { : i k 1 ? c ( gets w ) ( string_from `fresh inout` ) }
}

// Inout assignment with two fresh arms
@ put_inout_fresh inout String o b c → v {
    = o { : i k 1 ? c ( string_from `fresh y` ) ( string_from `fresh x` ) }
}

// Local variable assignment
@ local_assign b c → i {
    : ~ String o ( string_from `initial` )
    = o { : i k 1 ? c ( string_from `local y` ) ( string_from `local x` ) }
    ^ ( string_len o )
}

// Field store
@ put_field inout H h b c → v {
    : W w ( mkw `field local` )
    = . h s { : i k 1 ? c ( gets w ) ( string_from `field fresh` ) }
}

// Sink call argument (vec_push keeps the string)
@ push_sink inout ( Vec String ) v b c → v {
    ( vec_push [String] v { : i k 1 ? c ( string_from `pushed y` ) ( string_from `pushed x` ) } )
}

// Borrowing call argument
@ call_borrow b c → i {
    ^ ( slen { : i k 1 ? c ( string_from `borrowed y` ) ( string_from `borrowed x` ) } )
}

// Let binding initialized with block ending in join
@ let_bind b c → String {
    : String o { : i k 1 ? c ( string_from `let y` ) ( string_from `let x` ) }
    ^ o
}

@ main → i {
    : ~ String s ( string_from `initial` )
    ( put_inout s T )
    ( nurl_println ( string_data s ) )
    ( put_inout s F )
    ( nurl_println ( string_data s ) )

    ( put_inout_fresh s T )
    ( nurl_println ( string_data s ) )
    ( put_inout_fresh s F )
    ( nurl_println ( string_data s ) )

    ( nurl_println_int ( local_assign T ) )
    ( nurl_println_int ( local_assign F ) )

    : ~ H h @ H { ( string_from `h_init` ) }
    ( put_field h T )
    ( nurl_println ( string_data . h s ) )
    ( put_field h F )
    ( nurl_println ( string_data . h s ) )

    : ~ ( Vec String ) v ( vec_new [String] )
    ( push_sink v T )
    ( push_sink v F )
    ( nurl_println_int ( vec_len [String] v ) )

    ( nurl_println_int ( call_borrow T ) )
    ( nurl_println_int ( call_borrow F ) )

    : String ly ( let_bind T )
    ( nurl_println ( string_data ly ) )
    : String lx ( let_bind F )
    ( nurl_println ( string_data lx ) )

    ^ 0
}
