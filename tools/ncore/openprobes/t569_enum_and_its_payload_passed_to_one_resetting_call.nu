// map: §2.10 | A2 | rejected | - | agora #569: `( reset_read o s )` - the enum and its own payload handed to one call that resets the enum then reads the payload
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ reset_read inout Msg m String t → v {
    = m @ Msg { MNone }
    ( nurl_println ( string_data t ) )
}

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            ( reset_read o s )
        }
        MNone → {}
    }
    ^ 0
}
