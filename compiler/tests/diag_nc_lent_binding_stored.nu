// diag_nc_lent_binding_stored.nu — a binding of a value that cannot be
// copied, which the call that made it may lend (`: D d \ ( getr h )`,
// getr handing back `@ !D E { T . h d }`), stored where it is kept (`= .
// h2 d d`). The store is judged as a store of that call's result is: the
// call lends, the value cannot be copied, so it is refused — stored as
// its own, it was released by both h and h2 (agora #200).

$ `stdlib/core/string.nu`

: | E { Bad }

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ getr H h → !D E { ^ @ !D E { T . h d } }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ pick inout H h2 → !i E {
    : H h ( mkh )
    : D d \ ( getr h )
    = . h2 d d
    ^ @ !i E { T 0 }
}

@ main → i {
    : ~ H h2 ( mkh )
    ?? ( pick h2 ) { T _ → {} F _ → {} }
    ^ 0
}
