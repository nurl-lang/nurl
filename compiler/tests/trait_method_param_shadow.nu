// trait_method_param_shadow.nu — a LOCAL callable shadows a same-named
// trait/impl method at a call site (regression, 2026-08-11).
//
// The real-world break: `vec_free_with [A] v ( @ v A ) drop` calls its
// CALLBACK PARAMETER as `( drop . buf i )`. Importing any file with a
// `% Drop <T>` impl (stdlib/ext/sqlite.nu) registered `drop` as an impl
// method, and Group F's impl dispatch intercepted the call before the
// parameter was consulted: `path.nu`'s vec_free_with__String then died
// with "method 'drop' has no impl for receiver type 'String'" in any
// program importing both — which `nurlpkg install nurllama` does
// (history.nu → sqlite, everything → path). Worse than the error: a
// receiver type that DID have an impl would have silently dispatched to
// the impl instead of the parameter.
//
// Covered here, with a `% Drop Res` impl in scope the whole time:
//   1. non-generic fn with a fn-typed param named `drop`  → param wins
//   2. generic fn, same shape, instantiated at two types  → param wins
//      (String instantiation = the exact vec_free_with__String shape)
//   3. a stored closure BINDING named `drop`              → binding wins
//   4. the impl itself stays wired: auto-drop at scope exit still runs
//      the real destructor (a shadow gate that over-matched would have
//      broken dispatch for everyone)
//
// Each case lives in its own function so case 3's binding cannot
// shadow anything outside its scope.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Res { i id }

% Drop Res {
    @ drop Res r → v {
        ( nurl_print `impl-drop ` ) ( nurl_print ( nurl_str_int . r id ) ) ( nurl_print `\n` )
    }
}

// 1. Non-generic: the parameter named `drop` must be called, not the impl.
@ run_cb ( @ v i ) drop → v {
    ( drop 7 )
}

// 2. Generic: same, through instantiation (the shape vec_free_with has).
@ run_each [A] ( Vec A ) v ( @ v A ) drop → v {
    : i n ( vec_len [A] v )
    : *A buf # *A ( vec_data [A] v )
    : ~ i k 0
    ~ < k n {
        ( drop . buf k )
        = k + k 1
    }
}

// 3. A stored closure BINDING named `drop` shadows the impl method too.
@ binding_case → v {
    : ( @ v i ) drop \ i x → v { ( nurl_print `binding-cb ` ) ( nurl_print ( nurl_str_int x ) ) ( nurl_print `\n` ) }
    ( drop 9 )
    : *u __dropenv # *u drop 1
    ( nurl_free # s __dropenv )
}

// 4. No shadow in this scope: the destructor still runs via auto-drop.
@ impl_case → v {
    : Res r8 @ Res { 8 }
}

@ main → i {
    ( run_cb \ i x → v { ( nurl_print `param-cb ` ) ( nurl_print ( nurl_str_int x ) ) ( nurl_print `\n` ) } )

    : ( Vec i ) vi ( vec_new [i] )
    ( vec_push [i] vi 1 )
    ( vec_push [i] vi 2 )
    ( run_each [i] vi \ i x → v { ( nurl_print `gen-i ` ) ( nurl_print ( nurl_str_int x ) ) ( nurl_print `\n` ) } )
    ( vec_free [i] vi )

    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `aa` ) )
    ( run_each [String] vs \ String s → v { ( nurl_print `gen-s ` ) ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) ( string_free s ) } )
    ( vec_free [String] vs )

    ( binding_case )
    ( impl_case )
    ^ 0
}
