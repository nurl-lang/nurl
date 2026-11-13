// cursor_pushed_into_two_containers_the_second_a_copy_runs_clean: `: ~ cur t`, `( vec_push d cur )`, then `( vec_push d2 cur )`
// Kept: once a cursor's owner went with it, the cursor is a copy of an element's handle — storing it again takes no owner along, and is copied (agora #824's review).
// main 83059aae: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #824: a cursor pushed into two containers
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : ~ ( Vec i ) cur t
    : ~ ( Vec ( Vec i ) ) d ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] d cur )
    : ~ ( Vec ( Vec i ) ) d2 ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] d2 cur )
    ( nurl_println_int + ( vec_len [( Vec i )] d ) ( vec_len [( Vec i )] d2 ) )
    ^ 0
}
