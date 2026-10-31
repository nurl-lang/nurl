// nested_match_over_a_second_payload: agora #175 — the same over a variant's second payload (nested_match_over_a_second_payload).
// Closed: a payload binding of an enum is lent, as a scrutinee too (__enum_pl, __match_scrut_lent; agora #175).
// v0.80.0: accepted, ran clean. main after github#1306: dropped twice, heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h673 | agora #175: the same over a variant's second payload
$ `stdlib/core/string.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println ( nurl_str_cat `drop ` ( nurl_str_int . d n ) ) ) } }

@ mkd i n → D { ^ @ D { ( string_from `a string long enough to own a heap buffer here` ) n } }

: | E {
    Two i ? D
    NoVal
}

@ main → i {
    : E a @ E { Two 3 @ ?D { T ( mkd 8 ) } }
    ?? a { Two k o → { ?? o { T d → { ( nurl_println_int + k . d n ) } F → {} } } NoVal → {} }
    ^ 0
}
