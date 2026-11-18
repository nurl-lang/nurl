// map: §2.10 | A2 | rejected | - | AGORA-569: a view of the payload taken first, then passed after `( reset_ret o )` in one call
// AGORA-569 (this shape): refused on main 4db4cf5b by both nurlc and tools/ncore - closed by earlier work (AGORA-842's payload-cursor owners, AGORA-580, AGORA-428's copies); moved out of the open probes
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
