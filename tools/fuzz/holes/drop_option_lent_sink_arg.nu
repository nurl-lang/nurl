// drop_option_lent_sink_arg: agora #198 — the same with a `?D` (drop_option_lent_sink_arg).
// Closed: An option or a result of a value that cannot be copied is parked as the value itself (__nc_held_ty; agora #198).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h895 | agora #198: the same with a `?D`
$ `stdlib/core/string.nu`

: | E { Bad }

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ getr H h → ?D { ^ @ ?D { T . h d } }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ keepr sink ? D r → v {
    ?? r { T x → ( nurl_println_int ( string_len . x s ) ) F _ → ( nurl_println `bad` ) }
}

@ main → i {
    : H h ( mkh )
    ( keepr ( getr h ) )
    ^ 0
}
