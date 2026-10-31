// enum_struct_payload_returned_out_of_an_option_payload: agora #264 — as enum_payload_returned_out_of_an_option_payload, the payload a struct the enum holds in a box.
// Closed: an enum binding that owns its value where its flag says (`dyn`: an option's payload, a forward call's result) is one a match can take a payload out of; the take is made on the paths where the flag says it owns, and the payload handed out is owned exactly there (__m_take_slot, mem_enum_take; agora #264).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #264: a boxed struct payload returned out of an option payload's enum (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: P { ( Vec i ) a ( Vec i ) b i n }
: | Msg {
    MNone
    MSome P
}

@ make → ?Msg {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    ^ @ ?Msg { T @ Msg { MSome @ P { xs ( vec_new [i] ) 3 } } }
}

@ payload → P {
    ?? ( make ) {
        T m → { ?? m { MSome p → { ^ p } MNone → { ^ @ P { ( vec_new [i] ) ( vec_new [i] ) 0 } } } }
        F → { ^ @ P { ( vec_new [i] ) ( vec_new [i] ) 0 } }
    }
    ^ @ P { ( vec_new [i] ) ( vec_new [i] ) 0 }
}

@ main → i {
    : P got ( payload )
    ( vec_push [i] . got a 42 )
    ( nurl_println_int + ( vec_len [i] . got a ) . got n )
    ^ 0
}
