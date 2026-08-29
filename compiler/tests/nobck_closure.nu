// nobck_closure.nu — `--no-borrowck` on a program full of closures.
//
// The borrow checker is a DIAGNOSTIC pass: `--no-borrowck` is the escape
// hatch for a false positive, and switching it off must change nothing but
// the diagnostics. It did not. A closure body saved and restored the
// checker's own per-function state (`g_bck`) without the gate every other
// site uses, and `g_bck` only EXISTS when the checker is on — so with the
// flag the handle was 0 and `nurl_sym_get` hashed a key modulo a
// zero-capacity table: `internal compiler error: remainder by zero`, on
// every program containing a closure. Nothing in the tree ran the flag, so
// nothing caught it; this test is what runs it.
//
// Covers the closure shapes whose bodies drive different paths through
// that state: a bare statement body, a value-returning body, one that
// binds an owned string (the auto-drop bookkeeping), one that captures,
// and one nested inside another.
//
// Expected: COMPILE OK, LINK OK, EXIT 0.

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

@ fold ( Vec i ) v ( @ i i ) f → i {
    : i n ( vec_len [i] v )
    : ~ i acc 0
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] v k ) { T x → { = acc + acc ( f x ) } F _ → {} }
        = k + k 1
    }
    ^ acc
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    ( vec_push [i] v 40 )
    ( vec_push [i] v 500 )

    // Statement body, no return.
    ( each v \ i x → v { ( nurl_print_int x ) ( nurl_print ` ` ) } )
    ( nurl_print `\n` )

    // Value body, explicit return.
    : i total ( fold v \ i x → i { ^ * x 2 } )
    ( nurl_print_int total ) ( nurl_print `\n` )

    // Body that binds an owned string: the fall-off exit's drop epilogue
    // reclaims it, and the auto-drop bookkeeping is per-body state the
    // closure path has to keep straight in both checker modes.
    ( each v \ i x → v {
        : s ks ( nurl_str_int x )
        ( nurl_print ks )
    } )
    ( nurl_print `\n` )

    // A capture, and a closure nested inside a closure.
    : i bias 10
    : i biased ( fold v \ i x → i {
        : ( Vec i ) inner ( vec_new [i] )
        ( vec_push [i] inner x )
        : i one ( fold inner \ i y → i { ^ + y bias } )
        ( vec_free [i] inner )
        ^ one
    } )
    ( nurl_print_int biased ) ( nurl_print `\n` )

    ( vec_free [i] v )
    ^ 0
}
