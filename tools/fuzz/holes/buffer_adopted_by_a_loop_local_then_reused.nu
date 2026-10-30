// buffer_adopted_by_a_loop_local_then_reused: agora #160 — a value stored into an owner on some paths or iterations (buffer_adopted_by_a_loop_local_then_reused).
// Closed: a store survives joins and loop back-edges (agora #160).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.12 | A2 | rejected | h596 | agora #160: buffer_adopted_by_a_loop_local_then_reused
$ `stdlib/core/vec.nu`

: Img { i w ( Vec u ) d }

@ img_of i w ( Vec u ) data → Img { ^ @ Img { w data } }

@ main → i {
    : ( Vec u ) rgb ( vec_zeroed [u] 64 )
    : ~ i k 0
    ~ < k 3 {
        ( nurl_println_int ( vec_len [u] rgb ) )
        : Img im ( img_of 8 rgb )
        = k + k 1
    }
    ^ 0
}
