// should_fail_free_in_closure.nu — §2.1b reaches inside a closure body.
//
// The rule was scoped out of closures while only ONE of a closure's two
// exits ran the drop epilogue: a body returning through `^` freed what it
// registered, a body falling off its end freed nothing, so the hand-written
// free below was what kept that binding from leaking. Now that
// gen_closure_expr's fall-off exit runs the epilogue too, both exits free
// what they registered — registration is a proof inside a closure as much
// as outside one, and this free is the second one.
//
// The companion is `closure_falloff_drop.nu`, which runs the same shape
// WITHOUT the free and shows it is reclaimed anyway.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ each ( Vec i ) v ( @ v i ) f → v {
    : i n ( vec_len [i] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] v k ) { T x → ( f x ) F _ → {} }
        = k + k 1
    }
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 11 )
    ( each v \ i x → v {
        : s ks ( nurl_str_int x )
        ( nurl_print ks )
        ( nurl_free # s ks )
    } )
    ( vec_free [i] v )
    ^ 0
}
