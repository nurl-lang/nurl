// map: §2.10 | A2 | rejected | - | agora #569: a nested enum's payload read after `= o @ Outer { ONone }` in its arm
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }
: | Outer { ONone OIn Msg }

@ main → i {
    : ~ Outer o @ Outer { OIn @ Msg { MSome ( string_from `the inner message string long enough for the heap` ) } }
    ?? o {
        OIn inner → {
            ?? inner {
                MSome s → {
                    = o @ Outer { ONone }
                    ( nurl_println ( string_data s ) )
                }
                MNone → {}
            }
        }
        ONone → {}
    }
    ^ 0
}
