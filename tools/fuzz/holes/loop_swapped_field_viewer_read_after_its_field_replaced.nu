// loop_swapped_field_viewer_read_after_its_field_replaced: agora #318 — a field's viewer swapped with another cursor every pass (`= cur nxt = nxt tmp`), read after the field is replaced on the second pass: by then it holds the other field, and the cursor that took its place holds the freed one.
// Closed: at a loop head a binding stays the field's viewer only where the path back into it owns what it holds (the replace handed it the old value); one that path bound to another borrow is a plain borrow of both sources, which the replace ends (__fv_owned, agora #318).
// main: rejected; the first fix for agora #318 accepted it and AddressSanitizer reported heap-use-after-free.
// map: §2.6 | A1 | rejected | - | agora #318: a field viewer swapped with another cursor every pass, read after its field was replaced
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
    ~ < k 3 {
        ? == k 1 { = . sc b ( vec_new [i] ) } {}
        ( nurl_println_int ( vec_len [i] nxt ) )
        : ( Vec i ) tmp cur
        = cur nxt
        = nxt tmp
        = k + k 1
    }
    ( nurl_println_int ( vec_len [i] cur ) )
    ( nurl_println_int ( vec_len [i] nxt ) )
    ^ 0
}
