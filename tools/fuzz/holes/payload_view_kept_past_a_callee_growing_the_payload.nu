// map: §2.10 | A2 | rejected | - | AGORA-569: a `string_data` view of an enum's payload kept past a callee growing the payload through the enum
// AGORA-569 (this shape, closed): refused (main 029b01dd: accepted, heap-use-after-free)
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
            : s d ( string_data s )
            ( grow o )
            ( nurl_println d )
        }
        MNone → {}
    }
    ^ 0
}
