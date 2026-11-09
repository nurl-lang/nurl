// while_condition_reads_a_borrow_its_body_ended: agora #482 — `~ < i ( vec_len b )` over `b = ( vec_at vv 0 )`; the body clears `vv`; the condition reads `b` again at the next round
// Closed: a `~ cond` loop re-checks its condition's reads under the converged head, where a borrow its body ended is INVALID (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.6 | A2 | rejected | - | agora #482: a while condition reads a borrow its body ended
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec String ) b ( vec_at [( Vec String )] vv 0 )
    : ~ i i 0
    ~ < i ( vec_len [String] b ) {
        ( vec_clear [( Vec String )] vv )
        = i + i 1
    }
    ( nurl_println_int i )
    ^ 0
}
