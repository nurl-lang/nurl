// closure_returned_in_struct.nu — a closure literal inside a returned
// struct literal is returned with it, exactly as `^ \ → …` is: the Vec it
// captured moves into its env. It used to stay the function's, which
// dropped it at the return — so the caller ran the closure on a freed Vec
// (it printed 24 for a 2-element Vec). Under the sanitizer run this is
// also the proof that the env, dropped with the struct, frees it once.

$ `stdlib/core/vec.nu`

: Box { ( @ i ) f }

@ mk_box i n → Box {
    : ( Vec i ) a ( vec_new [i] )
    : ~ i k 0
    ~ < k n { ( vec_push [i] a k ) = k + k 1 }
    ^ @ Box { \ → i { ^ ( vec_len [i] a ) } }
}

@ main → i {
    : ~ i t 0
    : ~ i j 0
    ~ < j 50 {
        : Box b ( mk_box j )
        : ( @ i ) g . b f
        = t + t ( g )
        = j + j 1
    }
    ( nurl_println_int t )
    ^ 0
}
