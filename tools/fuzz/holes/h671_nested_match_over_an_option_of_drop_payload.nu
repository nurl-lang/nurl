// H671: agora #175 — a match over an enum payload that is an option of a % Drop type (nested_match_over_an_option_of_drop_payload).
// Closed: a payload binding of an enum is lent, as a scrutinee too (__enum_pl, __match_scrut_lent; agora #175).
// v0.80.0: accepted; LeakSanitizer (the enum dropped none of it). main after github#1306: the inner payload binding took the value over and the enum dropped it again, heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println ( nurl_str_cat `drop ` ( nurl_str_int . d n ) ) ) } }

@ mkd i n → D { ^ @ D { ( string_from `a string long enough to own a heap buffer here` ) n } }

: | E {
    Opt ? D
    NoVal
}

@ make i n → E { ^ @ E { Opt @ ?D { T ( mkd n ) } } }

@ main → i {
    : E a ( make 1 )
    : ~ E b ( make 2 )
    = b ( make 3 )
    ?? a { Opt o → { ?? o { T d → { ( nurl_println_int . d n ) } F → {} } } NoVal → {} }
    ^ 0
}
