// enum_payload_returned_out_of_a_channel_reply: agora #264 — as enum_payload_returned_out_of_an_option_payload, the option a `chan_recv` reply.
// Closed: an enum binding that owns its value where its flag says (`dyn`: an option's payload, a forward call's result) is one a match can take a payload out of; the take is made on the paths where the flag says it owns, and the payload handed out is owned exactly there (__m_take_slot, mem_enum_take; agora #264).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #264: an enum payload returned out of a channel reply (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/channel.nu`

: | Msg {
    MNone
    MSome ( Vec i )
}

@ payload ( Channel Msg ) ch → ( Vec i ) {
    ?? ( chan_recv [Msg] ch ) {
        T m → { ?? m { MSome v → { ^ v } MNone → { ^ ( vec_new [i] ) } } }
        F → { ^ ( vec_new [i] ) }
    }
    ^ ( vec_new [i] )
}

@ main → i {
    : ( Channel Msg ) ch ( chan_new [Msg] )
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    : b _s ( chan_send [Msg] ch @ Msg { MSome xs } )
    : ( Vec i ) got ( payload ch )
    ( vec_push [i] got 42 )
    ( nurl_println_int ( vec_len [i] got ) )
    ^ 0
}
