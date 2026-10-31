// enum_payload_returned_out_of_an_option_payload: agora #264 — a payload returned out of an enum that is itself an option's payload (`?? ( make ) { T m → ?? m { MSome v → ^ v } }`): the enum was dropped with the payload in it.
// Closed: an enum binding that owns its value where its flag says (`dyn`: an option's payload, a forward call's result) is one a match can take a payload out of; the take is made on the paths where the flag says it owns, and the payload handed out is owned exactly there (__m_take_slot, mem_enum_take; agora #264).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #264: an enum payload returned out of an option payload (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: | Msg {
    MNone
    MSome ( Vec i )
}

@ make → ?Msg {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    ^ @ ?Msg { T @ Msg { MSome xs } }
}

@ payload → ( Vec i ) {
    ?? ( make ) {
        T m → {
            ?? m {
                MSome v → { ^ v }
                MNone → { ^ ( vec_new [i] ) }
            }
        }
        F → { ^ ( vec_new [i] ) }
    }
    ^ ( vec_new [i] )
}

@ main → i {
    : ( Vec i ) got ( payload )
    ( vec_push [i] got 42 )
    ( nurl_print_int ( vec_len [i] got ) )
    ( nurl_print `\n` )
    ^ 0
}
