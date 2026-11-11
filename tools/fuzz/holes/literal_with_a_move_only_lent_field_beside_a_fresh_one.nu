// literal_with_a_move_only_lent_field_beside_a_fresh_one: agora #635 — `^ @ SE { ( string_from … ) . h inner }`, h a borrowed parameter and `inner` a value that cannot be copied: lent whole the fresh field leaks, owned whole the lent one is dropped twice.
// Closed: a plain struct literal handed on with a field of its own beside a field lent as is copies the lent fields, so it owns every field (gen_agg_lit), or is refused where one cannot be copied.
// main: accepted; LeakSanitizer reported the fresh field leaked.
// map: §7.6 | A2 | rejected | - | agora #635: `^ @ SE { ( string_from … ) . h inner }`, h a borrowed parameter and `inner` a value that cannot be copied: lent whole the fresh field leaks, owned whole the lent one is dropped twice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

: SE { String name Bomb b }

@ f Holder h → SE { ^ @ SE { ( string_from `a fresh name long enough for the heap` ) . h inner } }

@ main → i {
    : Holder h @ Holder { ( string_from `nm` ) ( bomb `inner` 0 ) }
    : SE r ( f h )
    ( see `main` . r b )
    ( see `main` . h inner )
    ^ 0
}
