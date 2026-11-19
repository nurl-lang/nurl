// map: §2.10 | A2 | rejected | - | AGORA-569: a nested enum's payload read after `= o @ Outer { ONone }` in its arm
// AGORA-569 (this shape, closed): refused (main 029b01dd: accepted, heap-use-after-free)
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
