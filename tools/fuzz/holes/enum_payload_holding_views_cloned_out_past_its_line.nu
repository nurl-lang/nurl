// enum_payload_holding_views_cloned_out_past_its_line: a `??` payload that is a Vec of views, cloned into an outer binding past the String.
// Closed: a `??` payload of an owner that holds views holds what that owner views: a view payload borrows it (`__vpay_srcs`), one that holds views itself depends on it (gen_match's `%` mark; agora #338).
// main 24e95a81: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #338: a `??` payload that is a Vec of views, cloned into an outer binding past the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Pkt { Toks ( Vec s ) NoToks String }

@ main → i {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : ( Vec s ) v ( vec_new [s] )
        ( vec_push [s] v ( string_data line ) )
        : Pkt p @ Pkt { Toks v }
        ?? p { Toks xs → { = keep ( vec_clone [s] xs ) } NoToks e → {} }
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}
