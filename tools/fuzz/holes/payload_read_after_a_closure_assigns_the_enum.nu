// map: §2.11 | A2 | rejected | - | AGORA-569: an enum arm's payload read after a closure that assigns the enum is run
// AGORA-569 (this shape, closed): refused (main 029b01dd: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    : ( @ v ) f \ → v { = o @ Msg { MNone } }
    ?? o {
        MSome s → {
            ( f )
            ( nurl_println ( string_data s ) )
        }
        MNone → {}
    }
    ^ 0
}
