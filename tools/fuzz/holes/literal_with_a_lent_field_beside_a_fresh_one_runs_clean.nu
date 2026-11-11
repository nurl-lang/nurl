// literal_with_a_lent_field_beside_a_fresh_one_runs_clean: agora #635 — `^ @ P2 { . h name ( string_from … ) }`, h a borrowed parameter — bare and inside a returned option: the lent field is copied, so the literal owns both; with every field lent (`^ @ P2 { . h name . h name }`) it stays a lend and nothing is copied.
// Closed: a plain struct literal handed on with a field of its own beside a field lent as is copies the lent fields, so it owns every field (gen_agg_lit), or is refused where one cannot be copied.
// main: accepted; LeakSanitizer reported the fresh field leaked (the whole literal was taken for a lend).
// map: §7.6 | A2 | runs-clean | - | agora #635: `^ @ P2 { . h name ( string_from … ) }`, h a borrowed parameter — bare and inside a returned option: the lent field is copied, so the literal owns both; with every field lent (`^ @ P2 { . h name . h name }`) it stays a lend and nothing is copied
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

: P2 { String a String b }

@ mk Holder h → P2 { ^ @ P2 { . h name ( string_from `a rather long fresh string value here` ) } }

@ mko Holder h b c → ?P2 {
    ? c { ^ @ ?P2 { T @ P2 { . h name ( string_from `another long fresh string value here` ) } } } {}
    ^ @ ?P2 { F }
}

@ both Holder h → P2 { ^ @ P2 { . h name . h name } }

@ main → i {
    : Holder h @ Holder { ( string_from `a holder name long enough for the heap` ) ( bomb `mine.inner` 0 ) }
    : P2 r ( mk h )
    ( nurl_println ( string_data . r a ) )
    ( nurl_println ( string_data . r b ) )
    : ?P2 o ( mko h T )
    ?? o { T p → { ( nurl_println ( string_data . p a ) ) ( nurl_println ( string_data . p b ) ) } F → {} }
    : P2 l ( both h )
    ( nurl_println ( string_data . l b ) )
    ( nurl_println ( string_data . h name ) )
    ^ 0
}
