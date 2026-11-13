// enum_payload_handed_back_under_another_name_runs_clean: `?? e { EA s → { : String t s ^ t } … }` over a local enum a call made — t is the payload under another name, handed back.
// Agora #783 B: answered "lent" out of the local e, which dies on the way out — the caller read freed memory; `t` is that payload (__etake_of / __pl_alias_of), copied or taken as `^ s` is.
// map: §2.8 | A2 | runs-clean | - | agora #783: a payload handed back under another name is the caller's own
$ `stdlib/core/string.nu`

: | E { EA String EB i }

@ mke s t → E { ^ @ E { EA ( string_from t ) } }

@ gid [A] A x → A { ^ x }

@ f i k → String {
    : E e ( mke `a payload string long enough for the heap` )
    ?? e { EA s → { : String t s ^ t } EB j → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String r ( f 1 )
    ( nurl_println ( string_data r ) )
    ^ 0
}
