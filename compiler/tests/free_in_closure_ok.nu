// free_in_closure_ok.nu — `nurl_free` inside a closure body stays legal.
//
// The §2.1b rule (should_fail_free_autodropped.nu) rejects a hand-written
// `nurl_free` of a binding auto-drop registered, because the scope exit
// frees it again. Inside a CLOSURE body that premise does not hold yet:
//
//   * a closure that returns through `^` runs the drop epilogue
//     (gen_ret_term), so its owned strings are reclaimed; but
//   * a closure that falls off its end emits a bare `ret` and drops
//     nothing, so the same binding LEAKS unless the body frees it.
//
// Until the two exits agree, the rule is only sound outside a closure, and
// the free below has to keep compiling — `packages/swarm-mcp` has exactly
// this shape and it is what stops that tool leaking a key per group.
//
// Expected: COMPILE OK and a clean run.

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
    ( vec_push [i] v 22 )
    ( each v \ i x → v {
        : s ks ( nurl_str_int x )
        ( nurl_print ks )
        ( nurl_free # s ks )
    } )
    ( nurl_print `\n` )
    ( vec_free [i] v )
    ^ 0
}
