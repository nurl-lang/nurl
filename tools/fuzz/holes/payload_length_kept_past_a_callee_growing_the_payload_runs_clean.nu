// payload_length_kept_past_a_callee_growing_the_payload_runs_clean: AGORA-569 guard — a number read out of an enum's payload kept past a callee growing the payload through the enum: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-569 guard: a number read out of an enum's payload kept past a callee growing the payload through the enum: accepted
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ grow inout Msg m → v {
    ?? m {
        MSome x → { ( string_push_str x `a long tail that forces the buffer to move to a new allocation, surely, yes indeed` ) }
        MNone → {}
    }
}

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            : i n ( string_len s )
            ( grow o )
            ( nurl_println_int n )
        }
        MNone → {}
    }
    ^ 0
}
