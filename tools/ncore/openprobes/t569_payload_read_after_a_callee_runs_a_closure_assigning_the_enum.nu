// map: §2.11 | A2 | rejected | - | agora #569: an enum arm's payload read after `( call_it f )` runs a closure that assigns the enum
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ call_it ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    : ( @ v ) f \ → v { = o @ Msg { MNone } }
    ?? o {
        MSome s → {
            ( call_it f )
            ( nurl_println ( string_data s ) )
        }
        MNone → {}
    }
    ^ 0
}
