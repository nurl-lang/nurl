// payload_of_an_enum_with_its_own_drop_handed_back_under_another_name_is_refused: `: Bomb t s ^ t` of a payload that cannot be copied, out of an enum with a `% Drop` of its own owned outright.
// Control for agora #783 (claude-formal's condition): the payload take under another name is only for an enum the compiler drops; one whose destructor is a user impl is not taken apart (A2's TakeOK glue requirement, #616/#632), so `^ t` stays a copy or a refusal as `^ s` is.
// map: §2.8 | A2 | rejected | - | agora #783: a payload of an own-Drop enum handed back under another name is not taken out
$ `stdlib/core/string.nu`

: Bomb { String n }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( string_data . b n ) ) } }

: | Fd { FA Bomb FB i }

% Drop Fd { @ drop Fd e → v { ( nurl_println `drop Fd` ) } }

@ f i k → Bomb { : Fd e @ Fd { FA @ Bomb { ( string_from `a bomb inside an enum with its own drop` ) } } ?? e { FA s → { : Bomb t s ^ t } FB j → {} } ^ @ Bomb { ( string_from `none` ) } }

@ main → i { : Bomb r ( f 1 ) ^ 0 }
