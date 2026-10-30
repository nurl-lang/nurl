// H896: agora #198 — `@ P { ( getr h ) }`: a lent `?D` stored into a literal's field (drop_option_lent_literal_field).
// Closed: An option or a result of a value that cannot be copied is parked as the value itself (__nc_held_ty; agora #198).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

: P { ? D o }

@ getr H h → ?D { ^ @ ?D { T . h d } }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ mkp H h → P { ^ @ P { ( getr h ) } }

@ main → i {
    : H h ( mkh )
    : P p ( mkp h )
    ?? . p o { T x → ( nurl_println_int ( string_len . x s ) ) F → ( nurl_println `none` ) }
    ^ 0
}
