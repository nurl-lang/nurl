// H924: agora #200 — `: H h2 @ H { d }`, a literal this function keeps (drop_bound_local_literal).
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

@ pick b c → !i E {
    : H h ( mkh )
    : D d \ ( getr h )
    : H h2 @ H { d }
    ( nurl_println_int ( string_len . . h2 d s ) )
    ^ @ !i E { T 0 }
}

@ main → i {
    ?? ( pick T ) { T _ → {} F _ → {} }
    ^ 0
}
