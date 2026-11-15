// map: §2.10 | A2 | rejected | - | agora #569: a view of the payload taken first, then passed after `( reset_ret o )` in one call
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ reset_ret inout Msg m → i { = m @ Msg { MNone } ^ 0 }

@ show i k s t → v { ( nurl_println t ) }

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            : s d ( string_data s )
            ( show ( reset_ret o ) d )
        }
        MNone → {}
    }
    ^ 0
}
