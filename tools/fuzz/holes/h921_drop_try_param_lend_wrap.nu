// H921: agora #200 — `^ @ !D E { T \ ( getr h ) }`, h a parameter: a try field was not asked as its call is (drop_try_param_lend_wrap).
// Closed: A binding of a value that cannot be copied which a call may lend (`__nclk`, __nc_bind_lend_note) is judged as that call's result: a store that keeps it is refused when the call lends (h228), a `^` of it when the call may lend out of a local (agora #200).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E { Bad }

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ getr H h → !D E { ^ @ !D E { T . h d } }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ okd → !D E { ^ @ !D E { T @ D { ( string_from `fresh` ) } } }

@ pick H h → !D E {
    ^ @ !D E { T \ ( getr h ) }
}

@ main → i {
    : H h ( mkh )
    ?? ( pick h ) { T x → ( nurl_println_int ( string_len . x s ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
