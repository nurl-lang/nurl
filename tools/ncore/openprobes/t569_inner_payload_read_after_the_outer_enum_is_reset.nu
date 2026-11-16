// map: §2.10 | A2 | rejected | - | agora #569: a nested enum's payload read after the outer enum is reset by an inout callee
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }
: | Outer { ONone OIn Msg }

@ reseto inout Outer m → v { = m @ Outer { ONone } }

@ main → i {
    : ~ Outer o @ Outer { OIn @ Msg { MSome ( string_from `the inner message string long enough for the heap` ) } }
    ?? o {
        OIn inner → {
            ?? inner {
                MSome s → {
                    ( reseto o )
                    ( nurl_println ( string_data s ) )
                }
                MNone → {}
            }
        }
        ONone → {}
    }
    ^ 0
}
