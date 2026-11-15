// map: §2.10 | A2 | rejected | - | agora #569: `( show ( reset_ret o ) ( string_data s ) )` - the payload read as a later argument of the call that resets the enum
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ reset_ret inout Msg m → i { = m @ Msg { MNone } ^ 0 }

@ show i k s t → v { ( nurl_println t ) }

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            ( show ( reset_ret o ) ( string_data s ) )
        }
        MNone → {}
    }
    ^ 0
}
