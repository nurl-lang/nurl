// field_reader_rebound_string_returned: agora #268 — a String read out of a local struct's field, re-bound and returned: the struct dropped it under the caller.
// Closed: a binding re-bound from one read out of a field (`: R a . col res  : R b a`, or `= b a`) reads that same field: handed on, it takes the field out of the struct as the first one would, instead of a cursor over a binding that owns nothing to hand over (__mem_udrop_bind_flag; agora #268).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #268: a String field reader re-bound and returned (UAF)
$ `stdlib/core/string.nu`

: C { String name i rc }

@ answer i k → String {
    : C col @ C { ( string_from `a heap string long enough to be heap allocated` ) k }
    : String a . col name
    : String b a
    ^ b
}

@ main → i {
    : String s ( answer 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
