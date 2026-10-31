// drop_try_bound_pushed: agora #200 — `( vec_push [D] v d )` of that binding, `v` a parameter (drop_try_bound_pushed).
// Closed: A binding of a value that cannot be copied which a call may lend (`__nclk`, __nc_bind_lend_note) is judged as that call's result: a store that keeps it is refused when the call lends (h228), a `^` of it when the call may lend out of a local (agora #200).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h920 | agora #200: `( vec_push [D] v d )` of that binding, `v` a parameter
$ `stdlib/core/string.nu`

: | E { Bad }

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ getr H h → !D E { ^ @ !D E { T . h d } }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ put ( Vec D ) v → !i E {
    : H h ( mkh )
    : D d \ ( getr h )
    ( vec_push [D] v d )
    ^ @ !i E { T 0 }
}

@ main → i {
    : ( Vec D ) v ( vec_new [D] )
    ?? ( put v ) { T _ → {} F _ → {} }
    ( nurl_println_int ( string_len . ( vec_at [D] v 0 ) s ) )
    ^ 0
}
