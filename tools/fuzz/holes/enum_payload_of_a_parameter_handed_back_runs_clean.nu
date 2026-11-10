// enum_payload_of_a_parameter_handed_back_runs_clean: agora #462 — `?? e { Has c → { ^ c } … }`, e an enum parameter, c a `% Drop` payload: lent back as part of e (claude-holes x07)
// main 0b124982: double drop (heap-use-after-free): the payload went to the caller as owned.
// map: §2.10 | A2 | runs-clean | - | agora #462: `?? e { Has c → { ^ c } … }`, e an enum parameter, c a `% Drop` payload: lent back as part of e (claude-holes x07)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

: | EC { Nope Has Conn }

@ get EC e → Conn {
    ?? e { Has c → { ^ c } Nope → {} }
    ^ @ Conn { ( string_from `a fresh connection, a heap name` ) 0 }
}

@ main → i {
    : EC e @ EC { Has @ Conn { ( string_from `the enum's connection, a heap name` ) 3 } }
    : Conn a ( get e )
    ( nurl_println ( string_data . a name ) )
    ^ 0
}
