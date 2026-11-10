// view_loop_goes_on_to_its_next_view_after_what_they_view_grew: agora #492 — `~ v ws { ( nurl_println v ) grow line }`: the next round's v is a copy of a view that ended
// Closed: a round's element of a container that ended as a holder of views reads as that holder does (agora #492).
// main a403b20: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #492: `~ v ws { ( nurl_println v ) grow line }`: the next round's v is a copy of a view that ended
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ growstr String l → v {
    : ~ i k 0
    ~ < k 64 { ( string_push_str l ` and a long tail, so the buffer moves` ) = k + k 1 }
}

@ main → i {
    : ~ String line ( string_from `a line long enough for a heap buffer` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    ( vec_push [s] ws ( string_data line ) )
    ( vec_push [s] ws ( string_data line ) )
    : ~ i done 0
    ~ v ws {
        ( nurl_println v )
        ( growstr line )
    }
    ^ 0
}
