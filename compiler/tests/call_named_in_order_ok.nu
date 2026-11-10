// call_named_in_order_ok.nu — keyword calls that set their arguments in
// declared order take the positional path (agora #434): labels from the
// first argument on, a positional prefix, a defaulted parameter a label
// skips over, and the trailing defaults; and a reordering call still
// fills its slots by name.
$ `stdlib/core/io.nu`

@ f i a i b = 20 i c i d = 40 → i { ^ + + + a b c d }

@ main → i {
    ( nurl_println_int ( f a : 1 b : 2 c : 3 d : 4 ) )
    ( nurl_println_int ( f 1 c : 3 ) )
    ( nurl_println_int ( f a : 1 c : 3 d : 4 ) )
    ( nurl_println_int ( f 1 2 c : 3 ) )
    ( nurl_println_int ( f c : 3 a : 1 ) )
    ^ 0
}
