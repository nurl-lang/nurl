// nested_match_over_a_result_of_drop_payload: agora #175 — the same over a result of a % Drop type (nested_match_over_a_result_of_drop_payload).
// Closed: a payload binding of an enum is lent, as a scrutinee too (__enum_pl, __match_scrut_lent; agora #175).
// v0.80.0: accepted, ran clean. main after github#1306: dropped twice, heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h672 | agora #175: the same over a result of a % Drop type
$ `stdlib/core/string.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println ( nurl_str_cat `drop ` ( nurl_str_int . d n ) ) ) } }

@ mkd i n → D { ^ @ D { ( string_from `a string long enough to own a heap buffer here` ) n } }

: | E {
    Res ! D i
    NoVal
}

@ main → i {
    : E a @ E { Res @ !D i { T ( mkd 7 ) } }
    ?? a { Res r → { ?? r { T d → { ( nurl_println_int . d n ) } F x → {} } } NoVal → {} }
    ^ 0
}
