// A value block whose value is an owned slice — a literal, a call, the
// block's own binding, a struct holding one — hands it to what the block is
// the value of, once. A slice returned past a `;` defer and out of a loop
// body is the caller's; the ones left behind are released (agora #545).
$ `stdlib/core/string.nu`

: H { [i items i n }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }
@ slen [String a → i { : ~ i t 0 ~ x a { = t + t ( string_len x ) } ^ t }
@ mk → [i { ^ [i | 7 8] }

@ past_defers i n → [i {
    : [i a [i | 1 2 3]
    ; { ( nurl_println ( nurl_str_int ( sum a ) ) ) }
    ? == n 0 { ^ a } {}
    ? == n 1 { ^ [i | 1] } {}
    : ~ i k 0
    ~ < k 3 {
        : [i it [i | 7 7 7]
        = k + + k 1 - ( sum it ) 21
    }
    ^ [i | 100]
}

@ past_defers_s i n → [String {
    : [String a [String | ( string_from `a long enough string to be on the heap, a` )]
    ; { ( nurl_println ( nurl_str_int ( slen a ) ) ) }
    : [String w [String | ( string_from `a long enough string to be on the heap, w-w` )]
    ? == n 0 { ^ a } {}
    ? == n 1 { ^ w } {}
    : ~ i k 0
    ~ < k 3 {
        : [String it [String | ( string_from `a long enough string to be on the heap, it-it-it` )]
        ? == k 1 {
            ? == n 2 { ^ it } {}
            break
        } {}
        = k + k 1
    }
    ^ [String | ( string_from `a long enough string to be on the heap, lit-lit-lit-lit` )]
}

@ main → i {
    : [i a { : i n 3 [i | n n] }
    : [i a2 { : i n 4 ( mk ) }
    ( nurl_println ( nurl_str_int + ( sum a ) ( sum a2 ) ) )
    : ~ [i c [i | 0]
    = c { [i | 1 2] }
    = c { : [i t [i | 3 4] t }
    ~ x c { ( nurl_println ( nurl_str_int x ) ) }
    : H h { @ H { [i | 1 2] 2 } }
    ~ x . h items { ( nurl_println ( nurl_str_int x ) ) }
    : [i d { ( nurl_println `in` ) [i | 1 2] }
    ~ x d { ( nurl_println ( nurl_str_int x ) ) }
    : ~ i k 0
    ~ < k 3 {
        : [i r ( past_defers k )
        ( nurl_println ( nurl_str_int ( sum r ) ) )
        = k + k 1
    }
    = k 0
    ~ < k 4 {
        : [String r ( past_defers_s k )
        ( nurl_println ( nurl_str_int ( slen r ) ) )
        = k + k 1
    }
    ^ 0
}
