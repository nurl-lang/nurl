// non_copyable_field_pushed_into_a_vec: a field that cannot be copied, read out of a local struct and pushed into a Vec (`( vec_push [Conn] v . p c )`), went over while the struct kept it: the Vec and the struct each released it.
// Closed: the field read is lent (mem_lent_cond), so a callee that keeps it is rejected at module end (resolve_nc_lent_stores), as h230 rejects a lending call's result.
// v0.78.0: accepted; ASan reported heap-use-after-free in Conn's drop.
// map: §7.6 | A2 | rejected | h325 | the same field pushed into a Vec: the Vec and the struct each released it; lent, so the keeping callee is rejected at module end
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

: Plain {
    Conn c
    i n
}

: Box {
    Conn c
    i n
}

@ main → i {
    : Plain p @ Plain { @ Conn { ( string_from `x` ) } 1 }
    : ~ ( Vec Conn ) v ( vec_new [Conn] )
    ( vec_push [Conn] v . p c )
    ( nurl_println `ran` )
    ^ 0
}
