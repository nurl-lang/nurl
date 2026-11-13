// cursor_of_a_binding_pushed_then_the_owner_pushed_again: `: ~ cur t`, `( vec_push d cur )`, then `( vec_push d2 t )`: two owners of one buffer
// Closed: a `: ~` copy of an owner's handle that is stored (a literal, a field, a keeping call) takes its owner with it — the generated code hands the store the owner's own value — so the owner is moved from there; and a cursor over a parameter, stored into a literal or field the function keeps to itself, is copied as the parameter is (agora #824).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #824: the owner pushed again after its cursor was pushed
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : ~ ( Vec i ) cur t
    : ~ ( Vec ( Vec i ) ) d ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] d cur )
    : ~ ( Vec ( Vec i ) ) d2 ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] d2 t )
    ( nurl_println_int + ( vec_len [( Vec i )] d ) ( vec_len [( Vec i )] d2 ) )
    ^ 0
}
