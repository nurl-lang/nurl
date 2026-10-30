// H798: agora #186 — a `?` over a `% Drop` binding and a literal, bound by `:` (drop_join_bound).
// Closed: A `% Drop` value that cannot be copied, lent on one path and made on another, is answered per call as a String is: gen_cond / gen_match publish such a join's ownership (`__last_join_own__`), and the caller drops what it owns (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : D d @ D { ( mk ) }
    : ~ i k 0
    ~ < k 3 {
        : D x ? > k 0 d @ D { ( mk ) }
        ( nurl_println_int ( string_len . x s ) )
        = k + k 1
    }
    ^ 0
}
