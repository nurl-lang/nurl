// closure_capture_field_name.nu — a field name in a closure body is not a
// capture (agora #125, the field-name shape). `. q w` over a struct q reads
// q's field `w`; the capture scan took it for the outer Vec `w`, and the
// thread's closure moved a Vec it never touches, so the spawner's next
// `vec_push` was rejected ("use of moved value 'w'"). Through a pointer,
// `. p k` indexes by the value k, and stays a capture.

$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: P { i w i n }

@ main → i {
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 7 )
    : P p @ P { 3 4 }
    : !Thread ThreadErr t ( thread_spawn \ → v {
        : P q @ P { 5 6 }
        ( nurl_println_int . q w )
    } )
    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }
    ( vec_push [i] w 8 )
    ( nurl_println_int + ( vec_len [i] w ) . p w )
    ^ 0
}
