// drop_bound_field_store: agora #200 — `= . h2 d d` into an `inout` struct (drop_bound_field_store).
// Closed: A binding of a value that cannot be copied which a call may lend (`__nclk`, __nc_bind_lend_note) is judged as that call's result: a store that keeps it is refused when the call lends (h228), a `^` of it when the call may lend out of a local (agora #200).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h925 | agora #200: `= . h2 d d` into an `inout` struct
$ `stdlib/core/string.nu`

: | E { Bad }

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ getr H h → !D E { ^ @ !D E { T . h d } }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ okd → !D E { ^ @ !D E { T @ D { ( string_from `fresh` ) } } }

@ pick inout H h2 → !i E {
    : H h ( mkh )
    : D d \ ( getr h )
    = . h2 d d
    ^ @ !i E { T 0 }
}

@ main → i {
    : ~ H h2 ( mkh )
    ?? ( pick h2 ) { T _ → {} F _ → {} }
    ( nurl_println_int ( string_len . . h2 d s ) )
    ^ 0
}
