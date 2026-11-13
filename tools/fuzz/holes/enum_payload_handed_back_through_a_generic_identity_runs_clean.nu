// enum_payload_handed_back_through_a_generic_identity_runs_clean: `?? e { EA s → { ^ ( gid [String] s ) } … }` over a local enum a call made — the call lends the payload, handed back.
// Agora #783 B: the call lends out of a payload of an enum this frame releases (__payload_of_frame), a lend out of a local, copied on the way out; before, answered owned while the enum freed it.
// map: §2.8 | A2 | runs-clean | - | agora #783: a call lending a payload of a local enum, handed back, is copied
$ `stdlib/core/string.nu`

: | E { EA String EB i }

@ mke s t → E { ^ @ E { EA ( string_from t ) } }

@ gid [A] A x → A { ^ x }

@ f i k → String {
    : E e ( mke `a payload string long enough for the heap` )
    ?? e { EA s → { ^ ( gid [String] s ) } EB j → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String r ( f 1 )
    ( nurl_println ( string_data r ) )
    ^ 0
}
