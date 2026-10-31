// loop_swapped_cursor_read_after_its_other_source_replaced: agora #229 — two cursors over a struct's fields swapped every pass (`: ( Vec i ) tmp cur = cur nxt = nxt tmp`, stdlib/ext/regex.nu's matcher): on the second pass `tmp` holds what `nxt` held, and a field replaced before reading `tmp` freed it (loop_swapped_cursor_read_after_its_other_source_replaced).
// Closed: at a loop head a binding borrows from what it borrowed on either path into it — its borrow sources are joined (bck_loop, __bs_join), not left to whichever walk ran last (agora #229).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.6 | A1 | rejected | - | agora #229: a loop-carried cursor pair swapped every pass, read after the field it may hold on this pass was replaced
$ `stdlib/core/vec.nu`

: S { ( Vec i ) a ( Vec i ) b }

@ main → i {
    : ( Vec i ) va ( vec_new [i] )
    ( vec_push [i] va 1 )
    : ( Vec i ) vb ( vec_new [i] )
    ( vec_push [i] vb 2 )
    : ~ S sc @ S { va vb }
    : ~ ( Vec i ) cur . sc a
    : ~ ( Vec i ) nxt . sc b
    : ~ i k 0
    ~ < k 2 {
        : ( Vec i ) tmp cur
        ? == k 1 { = . sc b ( vec_new [i] ) } {}
        ( nurl_println_int ( vec_len [i] tmp ) )
        = cur nxt
        = nxt tmp
        = k + k 1
    }
    ^ 0
}
